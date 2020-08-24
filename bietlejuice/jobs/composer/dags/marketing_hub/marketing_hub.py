from datetime import datetime
import pendulum

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.base.datalake_sub_dag import DatalakeSubDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import FileService

SOURCE = "marketing_hub"
DAG_ID = f"bietlejuice.{SOURCE}"
ENV = Variable.get("environment")

DATALAKE_BUCKET = Variable.get("datalake_old_bucket")
S3_MARKETING_PATH = Variable.get("datalake_marketing_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)


local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "15 7 * * *"

GOOGLE_ADS_SOURCE_PATH = f"s3://{S3_MARKETING_PATH}/google-reports"
GOOGLE_ADS_TARGET_PATH = f"s3://{DATALAKE_BUCKET}/raw/marketing_hub/google_ads"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

google_ads_load_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="google-ads-load-to-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "google_ads_load_to_raw.py",
            "parameters": [
                GOOGLE_ADS_SOURCE_PATH,
                GOOGLE_ADS_TARGET_PATH,
                DATALAKE_BUCKET,
                ENV,
                "{{ ds }}",
            ],
        }
    },
)

try:
    media_names = FileService.list_layer_sql_files(SOURCE, "")
except RuntimeError:
    raise RuntimeError(
        f"m=marketing_hub stage=clean, dag_id={DAG_ID}, msg=There's no media in query folder"
    )

for media_name in media_names:

    media_layer = f"{media_name}/{LayerEnum.CLEAN.value}"

    sql_file_list = FileService.list_sql_files_without_extension_from_layer(
        SOURCE, media_layer
    )

    clean_sub_dag = DatalakeSubDAG(
        dag_id=DAG_ID,
        env=ENV,
        datalake_bucket=DATALAKE_BUCKET,
        layer=LayerEnum.CLEAN,
        database_base_name=SOURCE,
        relative_query_path=f"{SOURCE}/{media_name}",
        spark_job_paths=BASE_SPARK_JOBS_PATH,
        athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
        start_date=MAIN_START_DATE,
    )

    clean_sub_dags = clean_sub_dag.build_subdags_from_sql_files(
        dag,
        sql_file_list,
        is_incremental=True,
        partitions=["report_type", "acc", "campaign_name", "str_created_at"],
    )

    google_ads_load_to_raw_task >> list(
        clean_sub_dags.values()
    ) >> terminate_cluster_task

create_cluster_task >> google_ads_load_to_raw_task
