from datetime import datetime
import pendulum
import os

from airflow.utils.helpers import chain
from airflow.models import DAG
from airflow.operators.python_operator import ShortCircuitOperator
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_builders.main_builder.short_circuit_functions.dag_run_date_validators import (
    DAGRunDateValidators,
)
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers.task_flow_helper import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum


LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2021, 7, 20, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 6 * * *"
CONTEXT = "crawlers_listings"
DAG_NAME = f"enrich_rental_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(DAG_NAME)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
crawlers = config_service.get_config("tables")
cluster_description = config_service.get_config("custom_cluster")
weekday_run = config_service.get_config("weekday_run")

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
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
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

# The execution date will always be the previous day, because this DAG runs daily.
# However, it should be the previous week, because the source runs weekly. That is why we are subtracting 6 days.
actual_execution_date = "{{macros.ds_add(ds, -7)}}"

skip_run = ShortCircuitOperator(
        task_id=f"check-day-to-skip-execution",
        python_callable=DAGRunDateValidators.check_is_in_range_of_weekdays,
        op_args=[actual_execution_date, weekday_run],
)

chain(
    skip_run,
    create_cluster_task,
)

for crawler in crawlers:
    crawler_name = crawler["table_name"]
    is_incremental = crawler["is_incremental"]
    partition_cols = crawler["partition_cols"]

    enrich_task_groups[crawler_name] = datalake_task_group.build_enrich_task_group(
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        table_name=crawler_name,
        is_incremental=is_incremental,
        partitions=partition_cols,
        execution_date=actual_execution_date,
    )

    crawler_weekday = crawler["weekday_run"]
    skip_run_task = ShortCircuitOperator(
        task_id=f"check-day-to-skip-execution-{crawler_name}",
        python_callable=DAGRunDateValidators.check_is_specific_weekday,
        op_args=[actual_execution_date, crawler_weekday],
    )
    chain(
        create_cluster_task,
        skip_run_task,
        DatalakeTaskGroup.first_tasks(enrich_task_groups[crawler_name]),
    )

chain(
    DatalakeTaskGroup.all_last_tasks(enrich_task_groups),
    terminate_cluster_task,
)
