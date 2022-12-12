from datetime import datetime, timedelta
import pendulum
import os

from airflow.utils.helpers import chain
from airflow.models import DAG
from airflow.operators.python_operator import ShortCircuitOperator
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow import BaseDAG, BaseTaskGroup, DAGOwnerEnum
from bietlejuice.base.airflow.helpers.task_flow_helper import TaskFlowHelper
from bietlejuice.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum


def check_valid_run_date(dag_execution_date, table_day):
    lag_dag_execution_date = datetime.strptime(dag_execution_date, "%Y-%m-%d") + timedelta(days=1)
    return (
        lag_dag_execution_date.day in table_day
    )


LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2021, 7, 20, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 6 * * *"
CONTEXT = "sale_stranded_listings"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(DAG_NAME)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
tables = config_service.get_config("tables")
cluster_description = config_service.get_config("databricks_10_4_med_general_cluster")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
default_libraries = config_service.get_config("default_libraries")

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
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, 
    task_id="terminate-cluster", 
    trigger_rule="none_failed", 
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
inner_dependencies = {}
execution_date = "{{ds}}"

for table in tables:
    table_name = table["table_name"]
    is_incremental = table["is_incremental"]
    partition_cols = table.get("partitions")

    enrich_task_groups[table_name] = datalake_task_group.build_enrich_task_group(
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        table_name=table_name,
        is_incremental=is_incremental,
        partitions=partition_cols,
        execution_date=execution_date
    )
    
    table_day = table["day_run"]
    skip_run_task = ShortCircuitOperator(
        task_id=f"check-day-to-skip-execution-{table_name}",
        python_callable=check_valid_run_date,
        op_kwargs={"dag_execution_date": execution_date, "table_day": table_day},
        trigger_rule="none_failed", 
    )
    chain(create_cluster_task, skip_run_task, DatalakeTaskGroup.first_tasks(enrich_task_groups[table_name]))
(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = datalake_task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=enrich_task_groups,
    dag_inner_dependencies=inner_dependencies,
)

chain(
    BaseTaskGroup.all_last_tasks(task_groups_boundaries_without_inner_dependencies)
    + BaseTaskGroup.last_tasks(inner_dependencies_task_groups_boundaries),
    terminate_cluster_task,
)

# Set data quality tasks if exists
independent_tasks = DatalakeTaskGroup.all_independent_tasks(enrich_task_groups)
if independent_tasks:
    terminate_cluster_task.set_upstream(independent_tasks)