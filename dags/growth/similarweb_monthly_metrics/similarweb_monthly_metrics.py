from datetime import datetime
from dateutil.relativedelta import relativedelta
from pendulum import timezone
import os

from airflow.models import DAG
from airflow.utils.helpers import chain
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum


def get_previous_month(execution_date):
    return datetime.strftime(
        datetime.strptime(execution_date, "%Y-%m-%d").replace(day=1)
        - relativedelta(days=1),
        "%Y-%m",
    )


def get_executor_type_param(dag_run, default_executor_type, executor_type_param_name):
    executor_type_param = (
        dag_run.conf.get(executor_type_param_name) if dag_run.conf else None
    )
    if executor_type_param and executor_type_param in [
        "thread",
        "multiprocessing",
        "spark",
    ]:
        return executor_type_param
    return default_executor_type


SOURCE = "similarweb_monthly_metrics"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2021, 10, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 9 12 * *"
CLUSTER_DESCRIPTION = "databricks_12_2_med_general_cluster"

# Task params
TASK_POOL = "similarweb_pool"

config_service = ConfigurationService(SOURCE)
artifacts_bucket = config_service.get_config("artifacts_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/"

cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")
custom_libraries = config_service.get_config("custom_libraries")
custom_libraries[0]["whl"] = custom_libraries[0]["whl"].format(
    artifacts_bucket=artifacts_bucket
)

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
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
    user_defined_macros={
        "get_previous_month": get_previous_month,
        "get_executor_type_param": get_executor_type_param,
    },
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries + custom_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=SOURCE,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)

table_names = config_service.get_config("tables")

raw_task_groups = {}
clean_task_groups = {}
for table_name in table_names:
    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        table_name=table_name,
        target_database_base_name=SOURCE,
        extraction_spark_job_file=f"{RAW_SPARK_JOB_PATH}load_{SOURCE}_to_raw.py",
        raw_spark_job_extra_args=[
            SOURCE,
            table_name,
            "{{ get_previous_month(ds) }}",
            "{{ get_executor_type_param(dag_run, 'spark', 'executor_type') }}",
        ],
        pool=TASK_POOL,
    )
    raw_task_groups[table_name] = raw_task_group

    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        is_incremental=True,
        partitions=table_names[table_name]["clean_partition_cols"],
        has_create_external_table_task=False,
        extra_query_template_params={"previous_month": "{{ get_previous_month(ds) }}"},
    )
    clean_task_groups[table_name] = clean_task_group

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups))

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
