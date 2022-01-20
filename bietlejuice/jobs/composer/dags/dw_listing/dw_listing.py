import os
import pendulum
from datetime import datetime

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
from bietlejuice.jobs.composer.services import ConfigurationService

DW_SCHEMA = "public"
CONTEXT = "listing"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"


configs_service = ConfigurationService(DAG_NAME)
spectrum_iam_role = configs_service.get_config("spectrum_iam_role")
dw_bucket = configs_service.get_config("dw_bucket")
doc_md_chart_url = configs_service.get_config("doc_md_chart_url")
databricks_bietlejuice_repo_path = configs_service.get_config(
    "databricks_bietlejuice_repo_path"
)
spark_jobs_logs_path = configs_service.get_config("spark_jobs_logs_path")

ENV = os.environ.get("ENVIRONMENT")
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2021, 8, 2, 0, 0, 0, tzinfo=LOCAL_TZ)

SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base"
LOGS_OUTPUT_PATH = f"{spark_jobs_logs_path}{DAG_ID}"
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

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
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

dw_task_group = DWTaskGroup(
    dag=dag,
    env=ENV,
    dw_bucket=dw_bucket,
    dw_schema=DW_SCHEMA,
    relative_query_path=DAG_NAME,
    spark_jobs_path=SPARK_JOBS_PATH,
)

dw_staging_task_group = dw_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW_STAGING
)

dw_task_group = dw_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW, spectrum_iam_role=spectrum_iam_role
)

chain(create_cluster_task, DWTaskGroup.all_first_tasks(dw_staging_task_group))
TaskFlowHelper.chain_task_groups_via_common_table(dw_staging_task_group, dw_task_group)
chain(DWTaskGroup.all_last_tasks(dw_task_group), terminate_cluster_task)
