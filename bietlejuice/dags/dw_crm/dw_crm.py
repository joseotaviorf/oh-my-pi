from datetime import datetime
from pendulum import timezone
import os

from airflow.models import DAG
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.services.configuration_service import ConfigurationService

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG and Jobs params setup
DW_SCHEMA = "crm"
CONTEXT = "crm"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

MAIN_START_DATE = datetime(2020, 11, 1, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))

config_service = ConfigurationService(DAG_NAME)

# S3 paths setup
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
dw_bucket = config_service.get_config("dw_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
spectrum_iam_role = config_service.get_config("spectrum_iam_role")
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

cluster_description = config_service.get_config("databricks_10_4_med_memory_cluster")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

default_libraries = config_service.get_config("default_libraries")

full_tables = config_service.get_config("full_tables")
incremental_load_parameters = config_service.get_config("incremental_load_parameters")
inner_dependencies = config_service.get_config("inner_dependencies")

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
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DWTaskGroup(
    dag=dag,
    env=ENV,
    dw_bucket=dw_bucket,
    dw_schema=DW_SCHEMA,
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
)

dw_staging_task_group = {}
dw_task_group = {}
tables = task_group._get_table_names_from_sql_files(layer=LayerEnum.DW)
for table in tables:
    is_incremental = table not in full_tables
    partitions = incremental_load_parameters["partitions"] if is_incremental else None
    extra_query_template_params = (
        incremental_load_parameters["dw_query_filters"] if is_incremental else None
    )

    dw_staging_task_group[table] = task_group.build_dw_staging_task_group(
        table_name=table,
        is_incremental=is_incremental,
        partitions=partitions,
        extra_query_template_params=extra_query_template_params,
    )

    dw_task_group[table] = task_group.build_dw_task_group(
        table_name=table,
        is_incremental=is_incremental,
        spectrum_iam_role=spectrum_iam_role,
        partitions=partitions,
        extra_query_template_params=extra_query_template_params,
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

chain(DWTaskGroup.all_last_tasks(dw_task_group), terminate_cluster_task)
