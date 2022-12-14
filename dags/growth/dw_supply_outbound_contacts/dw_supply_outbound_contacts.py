import os
import pendulum
from datetime import datetime

from airflow.models import DAG
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.services import ConfigurationService


LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2022, 10, 1, 0, 0, 0, tzinfo=LOCAL_TZ)

DW_SCHEMA = "supply_outbound_contacts"
CONTEXT = "supply_outbound_contacts"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

configs_service = ConfigurationService(DAG_NAME)

DEFAULT_LIBRARIES = configs_service.get_config("default_libraries")
ENV = os.environ.get("ENVIRONMENT")
SPECTRUM_IAM_ROLE = configs_service.get_config("spectrum_iam_role")
DW_BUCKET = configs_service.get_config("dw_bucket")
DOC_MD_BASE_URL = configs_service.get_config("doc_md_chart_url")

S3_PREFIX = configs_service.get_config("databricks_bietlejuice_repo_path")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base"

CLUSTER_DESCRIPTION = configs_service.get_config("databricks_10_4_med_memory_cluster")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
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
    libraries=DEFAULT_LIBRARIES,
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
    layer=LayerEnum.DW_STAGING
)
dw_task_group = dw_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW,
    spectrum_iam_role=SPECTRUM_IAM_ROLE,
    has_load_to_redshift_task=False,
)

chain(create_cluster_task, DWTaskGroup.all_first_tasks(dw_staging_task_group))
TaskFlowHelper.chain_task_groups_via_common_table(dw_staging_task_group, dw_task_group)
chain(DWTaskGroup.all_last_tasks(dw_task_group), terminate_cluster_task)

# Set data quality tasks if exists
independent_tasks = DWTaskGroup.all_independent_tasks(dw_staging_task_group)
if independent_tasks:
    terminate_cluster_task.set_upstream(independent_tasks)
