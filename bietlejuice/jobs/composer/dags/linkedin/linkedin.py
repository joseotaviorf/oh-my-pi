from datetime import datetime
import json
import pendulum
import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.base.datalake_sub_dag import DatalakeSubDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import FileService

# ENV setup
ENV = Variable.get("environment")
API_KEY = Variable.get("linkedin_api_key")
API_SECRET = Variable.get("linkedin_api_secret")
REFRESH_TOKEN = Variable.get("linkedin_refresh_token")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")
AUTH = json.dumps(
    {"API_KEY": API_KEY, "API_SECRET": API_SECRET, "REFRESH_TOKEN": REFRESH_TOKEN}
)

# DAG params setup
SOURCE = "marketing_costs"
MEDIA = "linkedin"
DAG_ID = f"bietlejuice.{MEDIA}"

local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 6, 1, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"

# s3 paths setup
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
LOAD_LINKEDIN_INTO_DATALAKE_RAW_FILE_PATH = (
    S3_PREFIX + f"/spark_jobs/{MEDIA}/load_incremental_data_into_datalake_raw.py"
)
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{DAG_ID}"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base"

# cluster setup
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
CUSTOM_LIBRARIES = [
    {
        "whl": f"{ARTIFACTS_S3_BUCKET}/linkedin-client-python/"
        f"quintoandar_linkedin_client-latest-py3-none-any.whl"
    }
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(MEDIA).format(chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID),
)


create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=CUSTOM_LIBRARIES,
)

linkedin_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="linkedin-campaigns-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_LINKEDIN_INTO_DATALAKE_RAW_FILE_PATH,
            "parameters": [ENV, SOURCE, MEDIA, DATALAKE_BUCKET, AUTH, "{{ ds }}"],
        }
    },
)

sync_metastore_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-raw-tables",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "/sync_metastore_tables.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.RAW.value,
                SOURCE,
                "--all-tables",
            ],
        }
    },
)

validate_sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id="validate-sync-hive-metastore-table",
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "/validate_sync_metastore_tables.py",
            "parameters": [LayerEnum.RAW.value, SOURCE, "--all-tables"],
        }
    },
)

clean_sub_dag = DatalakeSubDAG(
    dag_id=DAG_ID,
    start_date=MAIN_START_DATE,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    layer=LayerEnum.CLEAN,
    database_base_name=SOURCE,
    relative_query_path=f"{SOURCE}/{MEDIA}",
    spark_job_paths=SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

file_list = FileService.list_sql_files_without_extension_from_layer(
    f"{SOURCE}/{MEDIA}", LayerEnum.CLEAN.value
)

clean_sub_dags = clean_sub_dag.build_subdags_from_sql_files(
    dag, file_list, is_incremental=True, partitions=["year", "month", "day"]
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> linkedin_to_datalake_raw_task >> list(
    clean_sub_dags.values()
) >> terminate_cluster_task

airflow_helpers.chain(
    linkedin_to_datalake_raw_task,
    sync_metastore_tables_task,
    validate_sync_metastore_table_task,
    terminate_cluster_task,
)
