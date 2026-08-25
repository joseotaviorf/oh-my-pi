import os
from datetime import datetime
from typing import Dict, List, Optional

from airflow import DAG

from bietlejuice.base.airflow.datasets.dataset_adder import DatasetAdder
from bietlejuice.base.airflow.job_cluster_engine import (
    attach_emr_job_cluster_finished_work_prerequisites,
    attach_emr_terminate_cluster_work_prerequisites,
    attach_job_cluster_engine_to_context,
    get_job_cluster_completion_sink,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.notification.gchat_callback import GchatCallback
from bietlejuice.base.sst.airflow.common.common import parse_parameters
from bietlejuice.base.sst.airflow.operators.base import SStPlaceholderOperator
from bietlejuice.services.configuration_service import ConfigurationService

DAG_NAME = "sfmc"
DAG_ID = f"bietlejuice.{DAG_NAME.replace('.', '_')}"
ENV = os.environ.get("ENVIRONMENT")
CONFIG_SERVICE = ConfigurationService(DAG_NAME)
DATABRICKS_CONN_ID = "databricks_new"
BIETLEJUICE_REPO_PATH = CONFIG_SERVICE.get_config("databricks_bietlejuice_repo_path")
BASE_SPARK_JOB_PATH = f"{BIETLEJUICE_REPO_PATH}/spark_jobs/sst_pipelines/"

RAW_SCHEMA = CONFIG_SERVICE.get_config("raw_schema")
CLEAN_SCHEMA = CONFIG_SERVICE.get_config("clean_schema")
DLQ_SCHEMA = CONFIG_SERVICE.get_config("dlq_schema")

TEAMS_CONFIG = CONFIG_SERVICE.get_config("teams_config")
SOURCE_PREFIX = CONFIG_SERVICE.get_config("source_prefix")
CSV_ENCODING = CONFIG_SERVICE.get_config("csv_encoding")
CLUSTER_ARGS = CONFIG_SERVICE.get_config("cluster")

bucket = CONFIG_SERVICE.get_config("datalake_bucket")


BASE_PARAMETERS = {
    "env": ENV,
    "dag_name": DAG_NAME,
    "bucket": bucket,
    "partition_date": "{{ data_interval_start | ds }}",
}


def build_dag_execution_context(dag: DAG) -> DagExecutionContext:
    context = DagExecutionContext(
        dag=dag,
        environment=ENV,
        bucket=bucket,
        base_spark_jobs_path=BASE_SPARK_JOB_PATH,
        dag_args={},
        workflow_args={},
        cluster_args=CLUSTER_ARGS,
        databricks_conn_id=DATABRICKS_CONN_ID,
    )
    attach_job_cluster_engine_to_context(context, CONFIG_SERVICE)
    return context


def create_execute_job_cluster_task(dag_execution_context: DagExecutionContext):
    return dag_execution_context.job_cluster_engine.create_execute_cluster_task(
        config_service=CONFIG_SERVICE,
        minimum_cluster_runtime_version=None,
        execute_job_cluster_local_id=None,
    )


def create_sst_task(
    dag_execution_context: DagExecutionContext,
    target_schema: str,
    target_table: Optional[str],
    entry_point: str,
    parameters: Dict[str, str],
    task_id: str = None,
):
    task_id = f"load_{target_schema}_{target_table}" if not task_id else task_id
    base_parameters = {
        **BASE_PARAMETERS,
        "target_schema": target_schema,
        "target_table": target_table,
        "job_name": task_id,
        **parameters,
    }
    entry_point = entry_point if entry_point.endswith(".py") else f"{entry_point}.py"
    # parse_parameters stringifies every value, so a None would reach the job as
    # the literal "None". The raw pipeline names its tables from table_prefix +
    # de_type and never reads target_table, so the flag is left out entirely.
    base_parameters = parse_parameters(
        {key: value for key, value in base_parameters.items() if value is not None}
    )
    return dag_execution_context.job_cluster_engine.create_spark_python_task(
        spark_job_path=f"{BASE_SPARK_JOB_PATH}{entry_point}",
        task_id=task_id,
        job_parameters=base_parameters,
        execution_timeout_hours=1,
    )


webhook_sfmc = CONFIG_SERVICE.get_config("webhook_sfmc")
gchat_callback = GchatCallback(webhook_url_variable=webhook_sfmc)

default_args = {
    "owner": "Data SS",
    "email_on_retry": False,
    "retries": 3,
    # Every write is a replaceWhere day overwrite, so days are independent and a
    # single red partition must not block every run after it.
    "depends_on_past": False,
    "on_failure_callback": gchat_callback.task_failure_alert,
}
with DAG(
    dag_id=DAG_ID,
    default_args=default_args,
    schedule_interval="0 0 * * *",
    start_date=datetime(2026, 8, 24),
    catchup=False,
    tags=["SST", "SFMC", "sfmc"],
    on_failure_callback=gchat_callback.dag_failure_alert,
    max_active_runs=1,
) as dag:
    dag_execution_context = build_dag_execution_context(dag)

    start = SStPlaceholderOperator(task_id="start_sfmc")
    end = SStPlaceholderOperator(task_id="end_sfmc")

    execute_job_cluster = create_execute_job_cluster_task(dag_execution_context)
    start >> execute_job_cluster

    clean_tasks: List = []
    for team_name, team_conf in TEAMS_CONFIG.items():
        de_types = team_conf["de_types"]

        # One task per team: the raw pipeline loops over de_types itself, and
        # table_prefix is what keeps two teams sharing a schema from writing
        # the same table.
        raw_task = create_sst_task(
            dag_execution_context=dag_execution_context,
            target_schema=RAW_SCHEMA,
            target_table=None,
            entry_point="sfmc/raw_v2",
            parameters={
                "team_name": team_name,
                "de_types": ",".join(de_types),
                "source_prefix": SOURCE_PREFIX,
                "table_prefix": f"{team_name}_",
                "csv_encoding": CSV_ENCODING,
            },
            task_id=f"load_{RAW_SCHEMA}_{team_name}",
        )

        for de_type in de_types:
            clean_task = create_sst_task(
                dag_execution_context=dag_execution_context,
                target_schema=CLEAN_SCHEMA,
                target_table=f"{team_name}_{de_type}",
                entry_point="sfmc/clean_v2",
                parameters={
                    "source_schema": RAW_SCHEMA,
                    "dlq_schema": DLQ_SCHEMA,
                    "sync_hive": "True",
                },
            )

            # Emit a per-table dataset event for the clean layer so downstream
            # DAGs can trigger on this DAG via dependencies.yaml.
            DatasetAdder.attach_dataset_to_task(clean_task)

            execute_job_cluster >> raw_task >> clean_task
            clean_tasks.append(clean_task)

    cluster_completion_sink = get_job_cluster_completion_sink(
        dag_execution_context, execute_job_cluster, end
    )
    attach_emr_job_cluster_finished_work_prerequisites(
        dag_execution_context,
        job_cluster_finished_task=end,
        work_completion_tasks=clean_tasks,
    )
    for clean_task in clean_tasks:
        clean_task >> cluster_completion_sink
    attach_emr_terminate_cluster_work_prerequisites(
        dag_execution_context,
        cluster_completion_sink,
        execute_job_cluster_task=execute_job_cluster,
        job_cluster_finished_task=end,
    )
