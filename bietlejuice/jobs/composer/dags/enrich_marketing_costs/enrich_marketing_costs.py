from datetime import datetime
import pendulum

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.base.datalake_sub_dag import DatalakeSubDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import FileService

SOURCE = "marketing_hub"
TARGET = "marketing_costs"
DAG_ID = f"bietlejuice.enrich_{TARGET}"
ENV = Variable.get("environment")

DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_MARKETING_PATH = Variable.get("datalake_marketing_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_marketing_costs_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)

(
    database_name,
    database_location,
    athena_database_name,
) = DatalakeMetastoreService.get_layer_info(
    ENV, TARGET, DATALAKE_BUCKET, LayerEnum.ENRICH.value
)

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
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

media_names = FileService.list_layer_sql_files(TARGET, "")

for media_name in media_names:

    media_layer = f"{media_name}/{LayerEnum.ENRICH.value}"

    sql_file_list = FileService.list_sql_files_without_extension_from_layer(
        TARGET, media_layer
    )

    enrich_sub_dag = DatalakeSubDAG(
        dag_id=DAG_ID,
        env=ENV,
        datalake_bucket=DATALAKE_BUCKET,
        layer=LayerEnum.ENRICH,
        database_base_name=SOURCE,
        target_database_base_name=TARGET,
        relative_query_path=f"{TARGET}/{media_name}",
        spark_job_paths=BASE_SPARK_JOBS_PATH,
        athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
        start_date=MAIN_START_DATE,
    )

    enrich_sub_dags = enrich_sub_dag.build_subdags_from_sql_files(
        dag, sql_file_list, is_incremental=True, partitions=["acc", "load_date"]
    )

create_cluster_task >> list(enrich_sub_dags.values()) >> terminate_cluster_task
