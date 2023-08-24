from datetime import datetime
from pendulum import timezone
import os

from airflow.models import DAG
from airflow.utils.helpers import chain
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.dw_task_group_all_purpose import (
    DWTaskGroupAllPurpose,
)
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.services.configuration_service import ConfigurationService

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG and Jobs params setup
CONTEXT = "crm"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2020, 11, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None

config_service = ConfigurationService(DAG_NAME)
dw_bucket = config_service.get_config("dw_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
default_libraries = config_service.get_config("default_libraries")

tables_customization = config_service.get_config("tables_customization")
inner_dependencies = config_service.get_config("inner_dependencies")

cluster_description = config_service.get_config(
    "databricks_10_4_med_memory_photon_cluster"
)
dag_documentation = config_service.get_config("dag_documentation")

databricks_cluster_access_control_list = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
DAG_OWNER = DAGOwnerEnum.DATA_SS

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=DAG_NAME,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=dag_documentation,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        dag_owner=DAG_OWNER,
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    databricks_conn_id="databricks_job_cluster",
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    access_control_list=databricks_cluster_access_control_list,
    libraries=default_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    databricks_conn_id="databricks_job_cluster", dag=dag, task_id="terminate-cluster"
)

task_group = DWTaskGroupAllPurpose(
    dag=dag,
    env=ENV,
    dw_bucket=dw_bucket,
    dw_schema=CONTEXT,
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
)

table_names = task_group._get_table_names_from_sql_files(layer=LayerEnum.DW)

dw_staging_task_groups = {
    table_name: task_group.build_dw_staging_task_group(
        table_name=table_name,
        table_customization=tables_customization.get(table_name, {}),
    )
    for table_name in table_names
}

dw_task_groups = {
    table_name: task_group.build_dw_task_group(
        table_name=table_name,
        table_customization=tables_customization.get(table_name, {}),
    )
    for table_name in table_names
}

dw_task_group_boundaries = {}
for table in dw_task_groups:
    initial_tasks = DWTaskGroupAllPurpose.first_tasks(dw_staging_task_groups[table])
    final_tasks = DWTaskGroupAllPurpose.last_tasks(dw_task_groups[table])
    dw_task_group_boundaries[table] = DWTaskGroupAllPurpose.format_tasks_boundaries(
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
    DWTaskGroupAllPurpose.all_first_tasks(
        task_groups_boundaries_without_inner_dependencies
    )
    + DWTaskGroupAllPurpose.first_tasks(inner_dependencies_task_groups_boundaries),
)

TaskFlowHelper.chain_task_groups_via_common_table(
    dw_staging_task_groups, dw_task_groups
)

chain(DWTaskGroupAllPurpose.all_last_tasks(dw_task_groups), terminate_cluster_task)
