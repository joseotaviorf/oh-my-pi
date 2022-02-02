from datetime import datetime
from pendulum import timezone
import os

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

ENV = os.environ.get("ENVIRONMENT")

SOURCE = "braze_events"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{CONTEXT}"

MAIN_START_DATE = datetime(2020, 11, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "30 0 * * *"

config_service = ConfigurationService(SOURCE)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")

databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
raw_spark_job_file = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/load_braze_events_raw.py"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"

clean_partition_cols = config_service.get_config("clean_partition_cols")
braze_events_bucket = config_service.get_config("braze_events_bucket")
app_groups_list = config_service.get_config("app_groups_list")

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["spark_env_vars"]["ENVIRONMENT"] = ENV
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{spark_jobs_logs_path}{DAG_ID}"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(CONTEXT).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=CONTEXT,
    spark_jobs_path=base_spark_jobs_path,
    athena_query_result_location=athena_query_results_bucket,
)

raw_task_groups = {}
for app_group in app_groups_list:
    table_name = f"events_{app_group}"
    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=CONTEXT,
        table_name=table_name,
        target_database_base_name=CONTEXT,
        extraction_spark_job_file=raw_spark_job_file,
        raw_spark_job_extra_args=[CONTEXT, braze_events_bucket, app_group, "{{ ds }}"],
    )
    raw_task_groups[table_name] = raw_task_group

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
    is_incremental=True,
    partitions=clean_partition_cols,
)

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups))

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
