from datetime import datetime
import pendulum

from airflow.models import DAG, Variable
import airflow.utils.helpers as airflow_helpers
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.base.datalake_sub_dag import DatalakeSubDAG
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 8, 11, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "top_of_funnel_demand"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = Variable.get("environment")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base"

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

enrich_sub_dag = DatalakeSubDAG(
    dag_id=DAG_ID,
    start_date=MAIN_START_DATE,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    database_base_name=CONTEXT,
    relative_query_path=CONTEXT,
    spark_job_paths=SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
    layer=LayerEnum.ENRICH,
)

PARTITION_COLS = ["year", "month", "day"]

file_list = FileService.list_sql_files_without_extension_from_layer(
    CONTEXT, LayerEnum.ENRICH.value
)

enrich_sub_dags_incremental = enrich_sub_dag.build_subdags_from_sql_files(
    dag, file_list, is_incremental=True, partitions=PARTITION_COLS
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

tables_ordered = [
    "user_interactions",
    "first_user_interaction_staging",
    "first_user_interaction",
]

airflow_helpers.chain(
    create_cluster_task,
    enrich_sub_dags_incremental[tables_ordered[0]],
    enrich_sub_dags_incremental[tables_ordered[1]],
    enrich_sub_dags_incremental[tables_ordered[2]],
    terminate_cluster_task,
)
