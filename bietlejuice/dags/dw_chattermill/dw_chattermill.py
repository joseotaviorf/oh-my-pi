from datetime import datetime
import pendulum
import os

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum


LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2021, 2, 7, 0, 0, 0, tzinfo=LOCAL_TZ)

DW_SCHEMA = "chattermill"
CONTEXT = "chattermill"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
config_service = ConfigurationService(DAG_NAME)
SPECTRUM_IAM_ROLE = config_service.get_config("spectrum_iam_role")
DW_BUCKET = config_service.get_config("dw_bucket")

DATABRICKS_BIETLEJUICE_REPO_PATH = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
SPARK_JOBS_PATH = f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/base"
DOC_MD_BASE_URL = config_service.get_config("doc_md_chart_url")
SPARK_JOBS_LOGS_PATH = config_service.get_config("spark_jobs_logs_path")
LOGS_OUTPUT_PATH = f"{SPARK_JOBS_LOGS_PATH}{DAG_ID}"

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

default_libraries = config_service.get_config("default_libraries")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_BEDROCK,
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
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

dw_task_group = DWTaskGroup(
    dag=dag,
    env=ENV,
    dw_bucket=DW_BUCKET,
    dw_schema=DW_SCHEMA,
    relative_query_path=DAG_NAME,
    spark_jobs_path=SPARK_JOBS_PATH,
)

dw_staging_task_group = dw_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW_STAGING, has_ods_migration_test=False
)

dw_task_group = dw_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW, spectrum_iam_role=SPECTRUM_IAM_ROLE
)

chain(create_cluster_task, DWTaskGroup.all_first_tasks(dw_staging_task_group))
TaskFlowHelper.chain_task_groups_via_common_table(dw_staging_task_group, dw_task_group)
chain(DWTaskGroup.all_last_tasks(dw_task_group), terminate_cluster_task)
