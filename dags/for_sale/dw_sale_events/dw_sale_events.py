import os
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.dw_task_group import DWTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

# Pipeline inputs
DW_SCHEMA = "sale"
CONTEXT = "sale_events"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2020, 8, 6, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None
CLUSTER_DESCRIPTION = "databricks_10_4_med_general_cluster"

config_service = ConfigurationService(DAG_NAME)
dw_bucket = config_service.get_config("dw_bucket")
spectrum_iam_role = config_service.get_config("spectrum_iam_role")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")

inner_dependencies = config_service.get_config("inner_dependencies")
tables = config_service.get_config("tables")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
ENV = os.environ.get("ENVIRONMENT")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_SALE,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

dw_task_group = DWTaskGroup(
    dag=dag,
    env=ENV,
    dw_bucket=dw_bucket,
    dw_schema=DW_SCHEMA,
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
)

dw_staging_task_group = {}
dw_task_groups = {}

for table in tables:
    table_name = table["table_name"]
    is_incremental = table["is_incremental"]
    partition_cols = table.get("partitions")
    dw_query_filters = table.get("dw_query_filters")

    dw_staging_task_group[table_name] = dw_task_group.build_dw_staging_task_group(
        table_name=table_name,
        is_incremental=is_incremental,
        partitions=partition_cols,
        extra_query_template_params=dw_query_filters,
    )

    dw_task_groups[table_name] = dw_task_group.build_dw_task_group(
        table_name=table_name,
        is_incremental=is_incremental,
        spectrum_iam_role=spectrum_iam_role,
        partitions=partition_cols,
        extra_query_template_params=dw_query_filters,
    )

dw_task_group_boundaries = {}
for table in dw_task_groups:
    initial_tasks = DWTaskGroup.first_tasks(dw_staging_task_group[table])
    final_tasks = DWTaskGroup.last_tasks(dw_task_groups[table])
    dw_task_group_boundaries[table] = DWTaskGroup.format_tasks_boundaries(
        initial_tasks=initial_tasks, final_tasks=final_tasks
    )

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = dw_task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=dw_task_group_boundaries,
    dag_inner_dependencies=inner_dependencies,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

chain(
    create_cluster_task,
    DWTaskGroup.all_first_tasks(task_groups_boundaries_without_inner_dependencies)
    + DWTaskGroup.first_tasks(inner_dependencies_task_groups_boundaries),
)

TaskFlowHelper.chain_task_groups_via_common_table(dw_staging_task_group, dw_task_groups)

chain(
    DWTaskGroup.all_last_tasks(task_groups_boundaries_without_inner_dependencies)
    + DWTaskGroup.last_tasks(inner_dependencies_task_groups_boundaries),
    terminate_cluster_task,
)

# Set data quality tasks if exists
independent_tasks = DWTaskGroup.all_independent_tasks(dw_staging_task_group)
if independent_tasks:
    terminate_cluster_task.set_upstream(independent_tasks)
