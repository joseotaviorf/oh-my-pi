import os
import pendulum
from datetime import datetime, timedelta

from airflow.models import DAG
from airflow.utils.helpers import chain

from airflow.operators.python_operator import ShortCircuitOperator
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum


def check_valid_run_date(dag_execution_date):
    # get first day of the month
    first_day_of_month = (
        datetime.strptime(dag_execution_date, "%Y-%m-%d").date().replace(day=1)
    )

    # get day after first business day
    if first_day_of_month.weekday() > 4 or (  # weekends
        first_day_of_month.month in [1, 5]
        and first_day_of_month.weekday() == 4  # holiday on friday
    ):
        second_business_day_of_month = first_day_of_month + timedelta(
            days=-first_day_of_month.weekday() + 7
        )
    elif first_day_of_month.month in [1, 5]:  # first business day is a holiday
        second_business_day_of_month = first_day_of_month + timedelta(days=1)
    else:
        second_business_day_of_month = first_day_of_month

    if datetime.strptime(dag_execution_date, "%Y-%m-%d").day in [
        second_business_day_of_month.day
    ]:
        return True


LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 8, 29, 0, 0, 0, tzinfo=LOCAL_TZ)
ENV = os.environ.get("ENVIRONMENT")

CONTEXT = "fintech_snapshot"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

config_service = ConfigurationService(DAG_NAME)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
spectrum_iam_role = config_service.get_config("spectrum_iam_role")
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base"
CLUSTER_DESCRIPTION = config_service.get_config(
    "databricks_10_4_min_io-general_cluster"
)

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
        "owner": DAGOwnerEnum.DATA_FINTECH,
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
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

skip_run_task = ShortCircuitOperator(
    task_id=f"check-day-to-skip-execution",
    python_callable=check_valid_run_date,
    op_kwargs={"dag_execution_date": "{{ds}}"},
)

tables = config_service.get_config("tables")

dw_staging_task_group = {}
dw_task_group = {}
for table in tables:
    table_name = table["table_name"]
    datalake_schema = table.get("schema")
    partitions = ["year", "month", "day"]

    datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
    )
    partition_cols = config_service.get_config("partition_cols")

    enrich_task_groups = datalake_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.ENRICH,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
    is_incremental=True,
    has_create_external_table_task=False,
    partitions=partition_cols
    )

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = datalake_task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=enrich_task_groups,
    dag_inner_dependencies=inner_dependencies,
)


chain(
    skip_run_task,
    create_cluster_task,
    DatalakeTaskGroup.all_first_tasks(task_groups_boundaries_without_inner_dependencies)
    + DatalakeTaskGroup.first_tasks(inner_dependencies_task_groups_boundaries),
)

chain(
    skip_run_task,
    DatalakeTaskGroup.all_last_tasks(task_groups_boundaries_without_inner_dependencies)
    + DatalakeTaskGroup.last_tasks(inner_dependencies_task_groups_boundaries),
    terminate_cluster_task,
)
