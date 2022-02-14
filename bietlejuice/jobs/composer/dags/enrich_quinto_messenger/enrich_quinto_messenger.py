from datetime import datetime
import pendulum
import os

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 8, 29, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "quinto_messenger"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base"
LOGS_OUTPUT_PATH = f"s3://{Variable.get('databricks_s3_bucket')}/logs/jobs/{DAG_ID}"

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_quinto_messenger_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_SS,
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

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    relative_query_path=DAG_NAME,
    spark_jobs_path=SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

enrich_task_groups = datalake_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.ENRICH,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
)

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(enrich_task_groups))
chain(DatalakeTaskGroup.all_last_tasks(enrich_task_groups), terminate_cluster_task)
