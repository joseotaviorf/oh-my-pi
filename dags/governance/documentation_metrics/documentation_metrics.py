from datetime import datetime
from pendulum import timezone
import os

from airflow.models import DAG
from airflow.utils.helpers import chain
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService

ENV = os.environ.get("ENVIRONMENT")
SOURCE = "documentation_metrics"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2021, 10, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 5 * * *"

config_service = ConfigurationService(SOURCE)
datalake_bucket = config_service.get_config("datalake_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/"

cluster_description = config_service.get_config("databricks_10_4_med_general_cluster")
default_libraries = config_service.get_config("default_libraries")

EXECUTION_DATE = "{{ds}}"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GOVERNANCE,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    libraries=default_libraries,
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
    execution_timeout_hours=3,
)

table_names = config_service.get_config("table_names")
partition_cols = config_service.get_config("partition_cols")

raw_task_groups = {}
for table_name in table_names:
    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        table_name=table_name,
        target_database_base_name=SOURCE,
        extraction_spark_job_file=f"{RAW_SPARK_JOB_PATH}load_{table_name}_to_raw.py",
        raw_spark_job_extra_args=[SOURCE, table_name, EXECUTION_DATE]
    )
    raw_task_groups[table_name] = raw_task_group

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    is_incremental=True,
    partitions=partition_cols,
    execution_date=EXECUTION_DATE,
)

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups))

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
