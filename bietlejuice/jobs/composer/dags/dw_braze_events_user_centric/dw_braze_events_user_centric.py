from datetime import datetime
import pendulum
import os

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.jobs.composer.base.pipeline import LayerEnum

DW_SCHEMA = "braze"
CONTEXT = "braze_events_user_centric"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

ENV = os.environ.get("ENVIRONMENT")
DW_BUCKET = Variable.get("dw_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"

SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_small_memory_optimized_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 8, 29, 0, 0, 0, tzinfo=LOCAL_TZ)

INCREMENTAL_LOAD_PARAMETERS = {
    "partitions": ["year", "month", "day"],
    "dw_query_filters": {"year": "{year}", "month": "{month}", "day": "{day}"},
}

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
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

task_group = DWTaskGroup(
    dag=dag,
    env=ENV,
    dw_bucket=DW_BUCKET,
    dw_schema=DW_SCHEMA,
    relative_query_path=DAG_NAME,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
)

dw_staging_task_group = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW_STAGING,
    is_incremental=True,
    partitions=INCREMENTAL_LOAD_PARAMETERS["partitions"],
    extra_query_template_params=INCREMENTAL_LOAD_PARAMETERS["dw_query_filters"],
)

dw_task_group = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW,
    spectrum_iam_role=SPECTRUM_IAM_ROLE,
    is_incremental=True,
    partitions=INCREMENTAL_LOAD_PARAMETERS["partitions"],
    extra_query_template_params=INCREMENTAL_LOAD_PARAMETERS["dw_query_filters"],
)

chain(create_cluster_task, DWTaskGroup.all_first_tasks(dw_staging_task_group))

TaskFlowHelper.chain_task_groups_via_common_table(dw_staging_task_group, dw_task_group)

chain(DWTaskGroup.all_last_tasks(dw_task_group), terminate_cluster_task)
