from datetime import datetime
from pendulum import timezone
import os

from airflow.models import DAG
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

ENV = os.environ.get("ENVIRONMENT")
MAIN_START_DATE = datetime(2020, 8, 6, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))

DW_SCHEMA = "agent"
CONTEXT = "agent_contract"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

config_service = ConfigurationService(DAG_NAME)
SPECTRUM_IAM_ROLE = config_service.get_config("spectrum_iam_role")
DW_BUCKET = config_service.get_config("dw_bucket")
DOC_MD_CHART_URL = config_service.get_config("doc_md_chart_url")
DATABRICKS_BIETLEJUICE_REPO_PATH = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
BASE_SPARK_JOBS_PATH = f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/base"

CLUSTER_DESCRIPTION = config_service.get_config("databricks_10_4_med_general_cluster")
default_libraries = config_service.get_config("default_libraries")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

inner_dependencies = config_service.get_config("inner_dependencies")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_REDE,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_CHART_URL, dag_id=DAG_ID
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

task_group = DWTaskGroup(
    dag=dag,
    env=ENV,
    dw_bucket=DW_BUCKET,
    dw_schema=DW_SCHEMA,
    relative_query_path=DAG_NAME,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
)

dw_staging_task_group = {}
dw_task_group = {}
tables = config_service.get_config("tables")

for table in tables:
    table_name = table["table_name"]
    is_incremental = table["is_incremental"]
    partition_cols = table.get("partitions")
    dw_query_filters = table.get("dw_query_filters")

    dw_staging_task_group[table_name] = task_group.build_dw_staging_task_group(
        table_name=table_name,
        is_incremental=is_incremental,
        partitions=partition_cols,
        extra_query_template_params=dw_query_filters,
    )

    dw_task_group[table_name] = task_group.build_dw_task_group(
        table_name=table_name,
        spectrum_iam_role=SPECTRUM_IAM_ROLE,
        is_incremental=is_incremental,
        partitions=partition_cols,
        extra_query_template_params=dw_query_filters,
    )

dw_task_group_boundaries = {}
for table in dw_task_group:
    initial_tasks = DWTaskGroup.first_tasks(dw_staging_task_group[table])
    final_tasks = DWTaskGroup.last_tasks(dw_task_group[table])
    dw_task_group_boundaries[table] = DWTaskGroup.format_tasks_boundaries(
        initial_tasks=initial_tasks, final_tasks=final_tasks
    )

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=dw_task_group_boundaries,
    dag_inner_dependencies=inner_dependencies,
)

chain(
    create_cluster_task,
    DWTaskGroup.all_first_tasks(task_groups_boundaries_without_inner_dependencies)
    + DWTaskGroup.first_tasks(inner_dependencies_task_groups_boundaries),
)

TaskFlowHelper.chain_task_groups_via_common_table(dw_staging_task_group, dw_task_group)

chain(
    DWTaskGroup.all_last_tasks(task_groups_boundaries_without_inner_dependencies)
    + DWTaskGroup.last_tasks(inner_dependencies_task_groups_boundaries),
    terminate_cluster_task,
)

# Set data quality tasks if exists
independent_tasks = DWTaskGroup.all_independent_tasks(dw_staging_task_group)
if independent_tasks:
    terminate_cluster_task.set_upstream(independent_tasks)
