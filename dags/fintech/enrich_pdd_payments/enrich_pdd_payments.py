from datetime import datetime, date
import pendulum
import os
import pandas as pd

from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.operators.python_operator import ShortCircuitOperator

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from airflow.utils.helpers import chain
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.airflow.helpers.task_flow_helper import TaskFlowHelper
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum


def get_last_business_friday():
    bussiness_day = pd.date_range(date.today(), periods=1, freq="BM")
    return bussiness_day[0]


def check_valid_run_date(dag_execution_date):
    return (
        datetime.strptime(dag_execution_date, "%Y-%m-%d") == get_last_business_friday()
    )


LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2022, 1, 1, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "pdd_payments"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(DAG_NAME)

SPECTRUM_IAM_ROLE = config_service.get_config("spectrum_iam_role")
DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = config_service.get_config("athena_query_results_bucket")

S3_PREFIX = config_service.get_config("databricks_bietlejuice_repo_path")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base"
DOC_MD_BASE_URL = config_service.get_config("doc_md_chart_url")

SPARK_JOBS_LOGS_PATH = config_service.get_config("spark_jobs_logs_path")

LOGS_OUTPUT_PATH = f"{SPARK_JOBS_LOGS_PATH}{DAG_ID}"
default_libraries = config_service.get_config("default_libraries")
cluster_description = config_service.get_config("databricks_10_4_med_general_cluster")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

inner_dependencies = config_service.get_config("inner_dependencies")
incremental_tables = config_service.get_config("incremental_tables")
partition_cols = config_service.get_config("partition_cols")

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
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

datalake_task_groups = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    relative_query_path=DAG_NAME,
    spark_jobs_path=SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

tables = datalake_task_groups._get_table_names_from_sql_files(layer=LayerEnum.ENRICH)

enrich_task_groups = {}

for table in tables:
    is_incremental = table in incremental_tables
    partitions = partition_cols if table in incremental_tables else None
    enrich_task_groups[table] = datalake_task_groups.build_enrich_task_group(
        table_name=table,
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        is_incremental=is_incremental,
        partitions=partitions,
    )

skip_run_task = ShortCircuitOperator(
    task_id=f"check-day-to-skip-execution",
    python_callable=check_valid_run_date,
    op_kwargs={"dag_execution_date": "{{ds}}"},
)

skip_group = {
    "skip_execution": DatalakeTaskGroup.format_tasks_boundaries(
        initial_tasks=[skip_run_task], final_tasks=[skip_run_task]
    )
}

enrich_task_groups.update(skip_group)

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = datalake_task_groups.set_inner_dag_dependencies(
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
