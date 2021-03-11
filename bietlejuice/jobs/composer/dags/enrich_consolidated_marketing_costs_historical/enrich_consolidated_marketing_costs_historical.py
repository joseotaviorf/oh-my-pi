from datetime import datetime
import pendulum

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.base.datalake_sub_dag import DatalakeSubDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import FileService

SOURCE = "consolidated_marketing_costs"
DAG_NAME = f"enrich_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = Variable.get("environment")

DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_MARKETING_PATH = Variable.get("datalake_marketing_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/enrich_{SOURCE}/"
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_marketing_costs_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 0 1 * *"

EXECUTION_TIMEOUT_HOURS = 3

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

media_names = FileService.list_layer_sql_files(SOURCE, "")

for media_name in media_names:
    layers = FileService.list_layer_sql_files(SOURCE, media_name)
    enrich_layer = f"{media_name}/{LayerEnum.ENRICH.value}"
    sql_file_list = FileService.list_sql_files_without_extension_from_layer(
        SOURCE, enrich_layer
    )
    enrich_sub_dag = DatalakeSubDAG(
        dag_id=DAG_ID,
        env=ENV,
        datalake_bucket=DATALAKE_BUCKET,
        layer=LayerEnum.ENRICH,
        database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        relative_query_path=f"{SOURCE}/{media_name}",
        spark_job_paths=BASE_SPARK_JOBS_PATH,
        athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
        start_date=MAIN_START_DATE,
        execution_timeout_hours=EXECUTION_TIMEOUT_HOURS,
    )
    enrich_sub_dags = enrich_sub_dag.build_subdags_from_sql_files(
        dag, sql_file_list, is_incremental=False
    )

    create_cluster_task >> list(enrich_sub_dags.values()) >> terminate_cluster_task
