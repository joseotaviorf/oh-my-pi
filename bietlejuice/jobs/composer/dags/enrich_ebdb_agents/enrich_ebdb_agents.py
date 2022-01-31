import os
from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.operators.quintoandar_dag_logger import QuintoAndarSuccessLoggerOperator

from airflow.utils.helpers import chain

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseTaskGroup
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.base.airflow.helpers.task_flow_helper import (
    TaskFlowHelper,
)
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

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
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

tables = config_service.get_config("tables")

SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base"

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{spark_jobs_logs_path}{DAG_ID}"


INNER_DEPENDENCIES = {
    "agents_slots": [
        "agents_specific_weekly_schedule",
        "agents_weekly_schedule_history",
    ],
    "agents_slots_hourly": ["agents_slots"],
    "agents_weekly_schedule_history": ["slots_base_time"],
}

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
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
    dag_inner_dependencies=INNER_DEPENDENCIES,
)

chain(
    create_cluster_task,
    BaseTaskGroup.all_first_tasks(task_groups_boundaries_without_inner_dependencies)
    + BaseTaskGroup.first_tasks(inner_dependencies_task_groups_boundaries),
)

chain(
    BaseTaskGroup.all_last_tasks(task_groups_boundaries_without_inner_dependencies)
    + BaseTaskGroup.last_tasks(inner_dependencies_task_groups_boundaries),
    terminate_cluster_task,
)

# EC2 temporary dependency
success_logger = QuintoAndarSuccessLoggerOperator(
    dag=dag, bucket="5a-datalake-prod", aws_conn_id="aws_prod_data"
)
terminate_cluster_task >> success_logger
