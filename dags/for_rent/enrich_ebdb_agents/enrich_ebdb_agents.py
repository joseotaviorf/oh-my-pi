import os
from datetime import datetime

import pendulum
from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from airflow.utils.helpers import chain

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.airflow.helpers.task_flow_helper import TaskFlowHelper
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 7, 1, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "ebdb_agents"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")


config_service = ConfigurationService(DAG_NAME)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

tables = config_service.get_config("tables")

SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"

cluster_description = config_service.get_config("databricks_10_4_med_general_photon_cluster")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

# dependent: [dependencies]
inner_dependencies = config_service.get_config("inner_dependencies")

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
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)


terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)

enrich_task_groups = {}
for table in tables:
    table_name = table["table_name"]
    is_incremental = table["is_incremental"]
    partitions = table.get("partitions")
    task_group = datalake_task_group.build_enrich_task_group(
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        table_name=table_name,
        partitions=partitions,
        is_incremental=is_incremental,
    )
    enrich_task_groups[table_name] = task_group

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = datalake_task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=enrich_task_groups,
    dag_inner_dependencies=inner_dependencies,
)

chain(
    create_cluster_task,
    DatalakeTaskGroup.all_first_tasks(task_groups_boundaries_without_inner_dependencies)
    + DatalakeTaskGroup.first_tasks(inner_dependencies_task_groups_boundaries),
)

chain(
    DatalakeTaskGroup.all_last_tasks(task_groups_boundaries_without_inner_dependencies)
    + DatalakeTaskGroup.last_tasks(inner_dependencies_task_groups_boundaries),
    terminate_cluster_task,
)
