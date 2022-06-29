from datetime import datetime
from dateutil.relativedelta import relativedelta
from pendulum import timezone
import os

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)
from bietlejuice.jobs.composer.base.airflow.dag_owner_enum import DAGOwnerEnum


def get_week_start_date(execution_date):
    # substracted 8 days because some metrics are D-1 and others D-2
    return datetime.strptime(execution_date, "%Y-%m-%d") - relativedelta(days=8)


ENV = os.environ.get("ENVIRONMENT")
SOURCE = "similarweb_daily_metrics"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2021, 10, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "@weekly"

# Task params
TASK_POOL = "similarweb_pool"

config_service = ConfigurationService(SOURCE)
artifacts_s3_bucket = config_service.get_config("artifacts_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/"

CLUSTER_DESCRIPTION = Variable.get(
    f"databricks_minimum_resources_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["spark_env_vars"]["ENVIRONMENT"] = ENV
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{spark_jobs_logs_path}{DAG_ID}"

cluster_libs = config_service.get_config("cluster_libs")

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
        "get_week_start_date": get_week_start_date  # Macro can also be a function
    },
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=cluster_libs,
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
        raw_spark_job_extra_args=[SOURCE, table_name, "{{ get_week_start_date(ds) }}"],
        pool=TASK_POOL,
    )
    raw_task_groups[table_name] = raw_task_group

    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        is_incremental=True,
        partitions=table_names[table_name]["clean_partition_cols"],
        extra_query_template_params={
            "week_start_date": "{{ get_week_start_date(ds) }}"
        },
    )
    clean_task_groups[table_name] = clean_task_group

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups))

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
