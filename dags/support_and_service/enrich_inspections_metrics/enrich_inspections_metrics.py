from datetime import datetime

import pendulum
import os

from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService


CONTEXT = "inspections_metrics"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2022, 1, 19, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = None

config_service = ConfigurationService(DAG_NAME)

# s3 paths setup
datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")

s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

cluster_description = config_service.get_config("custom_cluster")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
DAG_OWNER = DAGOwnerEnum.DATA_SS

default_libraries = config_service.get_config("default_libraries")
inner_dependencies = config_service.get_config("inner_dependencies")

dag_documentation = config_service.get_config("dag_documentation")
incremental_tables = config_service.get_config("incremental_tables")
partitions_cols = config_service.get_config("partitions_cols")

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
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
    athena_query_result_location=athena_query_results_bucket,
)

enrich_task_groups = {}

tables = datalake_task_group._get_table_names_from_sql_files(layer=LayerEnum.ENRICH)

for table_name in tables:
    is_incremental = table_name in incremental_tables
    partitions = partitions_cols if is_incremental else None

    enrich_task_groups[table_name] = datalake_task_group.build_enrich_task_group(
        table_name=table_name,
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        has_create_external_table_task=False,
        is_incremental=is_incremental,
        partitions=partitions,
    )

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = datalake_task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=enrich_task_groups,
    dag_inner_dependencies=inner_dependencies,
)

create_cluster_task.set_downstream(
    DatalakeTaskGroup.all_first_tasks(task_groups_boundaries_without_inner_dependencies)
    + DatalakeTaskGroup.first_tasks(inner_dependencies_task_groups_boundaries)
)

terminate_cluster_task.set_upstream(
    DatalakeTaskGroup.all_last_tasks(task_groups_boundaries_without_inner_dependencies)
    + DatalakeTaskGroup.last_tasks(inner_dependencies_task_groups_boundaries)
)
