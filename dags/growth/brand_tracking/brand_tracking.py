import os
from datetime import datetime

import math
from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from dateutil.relativedelta import relativedelta
from pendulum import timezone

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum


def get_date_from_previous_quarter(execution_date):
    return datetime.strptime(execution_date, "%Y-%m-%d") - relativedelta(months=3)


def get_previous_quarter(execution_date):
    return math.ceil((get_date_from_previous_quarter(execution_date).month) / 3)


SOURCE = "brand_tracking"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None
CLUSTER_DESCRIPTION = "databricks_10_4_min_general_cluster"

config_service = ConfigurationService(SOURCE)
ATHENA_QUERY_RESULTS_BUCKET = config_service.get_config("athena_query_results_bucket")
DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
DATABRICKS_BIETLEJUICE_REPO_PATH = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
SPARK_JOBS_LOGS_PATH = config_service.get_config("spark_jobs_logs_path")
DOC_MD_CHART_URL = config_service.get_config("doc_md_chart_url")

cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")

PARTITION_COLS = config_service.get_config("partition_cols")
TABLES_LIST = config_service.get_config("tables_list")

RAW_SPARK_JOB_FILE = (
    f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/{SOURCE}/load_{SOURCE}_into_raw.py"
)
BASE_SPARK_JOBS_PATH = f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/base/"

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
        "owner": DAGOwnerEnum.DATA_GROWTH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=DOC_MD_CHART_URL, dag_id=DAG_ID
    ),
    user_defined_macros={
        # Macro can also be a function
        "get_date_from_previous_quarter": get_date_from_previous_quarter,
        "get_previous_quarter": get_previous_quarter,
    },
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    relative_query_path=SOURCE,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULTS_BUCKET,
)

raw_task_groups = {}
for table_name in TABLES_LIST:

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        extraction_spark_job_file=RAW_SPARK_JOB_FILE,
        raw_spark_job_extra_args=[
            SOURCE,
            table_name,
            "{{ get_date_from_previous_quarter(ds).year }}",
            "{{ get_previous_quarter(ds) }}",
        ],
    )
    raw_task_groups[table_name] = raw_task_group

    create_cluster_task >> DatalakeTaskGroup.first_tasks(raw_task_group)

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    is_incremental=True,
    partitions=PARTITION_COLS,
    has_create_external_table_task=False,
    extra_query_template_params={
        "year_previous_quarter": "{{ get_date_from_previous_quarter(ds).year }}",
        "previous_quarter": "{{ get_previous_quarter(ds) }}",
    },
)

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
