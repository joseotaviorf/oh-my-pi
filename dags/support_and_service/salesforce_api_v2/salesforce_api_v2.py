import os
from datetime import datetime
from typing import Dict, List

from airflow import DAG
from airflow.operators.python import ShortCircuitOperator

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

DAG_NAME = "salesforce_api_v2"
DAG_ID = f"bietlejuice.{DAG_NAME.replace('.', '_')}"
ENV = os.environ.get("ENVIRONMENT")
CONFIG_SERVICE = ConfigurationService(DAG_NAME)
DATABRICKS_CONN_ID = "databricks_new"
BIETLEJUICE_REPO_PATH = CONFIG_SERVICE.get_config("databricks_bietlejuice_repo_path")
BASE_SPARK_JOB_PATH = f"{BIETLEJUICE_REPO_PATH}/spark_jobs/sst_pipelines/"
RELATIVE_DAG_PATH = "dags/support_and_service/salesforce_api_v2"

RAW_SCHEMA = "datalake_salesforce_raw"
CLEAN_SCHEMA = "datalake_salesforce_clean"

OBJECTS_CONFIG = CONFIG_SERVICE.get_config("objects_config")
SALESFORCE_ENDPOINT = CONFIG_SERVICE.get_config("salesforce_endpoint")
CLUSTER_ARGS = CONFIG_SERVICE.get_config("cluster")

bucket = CONFIG_SERVICE.get_config("datalake_bucket")

# Wall-clock UTC hour at which daily (hourly: false) objects run. The DAG is
# scheduled hourly; the run whose data_interval_end lands on this hour is the
# one that processes the previous complete day for daily objects — every other
# run short-circuits them (see the gate below).
DAILY_EXECUTION_HOUR = CONFIG_SERVICE.get_config("daily_execution_hour")

BASE_PARAMETERS = {
    "env": ENV,
    "dag_name": DAG_NAME,
    "bucket": bucket,
    "partition_date": "{{ data_interval_start | ds }}",
}

# Daily objects must process a COMPLETE day. Under the hourly schedule the run
# executing at DAILY_EXECUTION_HOUR has data_interval_end on that hour, so the
# completed day is data_interval_end minus one day — for hour 0 this is
# byte-identical to the old daily schedule (executes at D+1 00:00, processes D).
# Using data_interval_start | ds here would point at a day that is still ~23h
# in the future and silently lose most of its updates.
DAILY_PARTITION_DATE = "{{ macros.ds_add(data_interval_end | ds, -1) }}"


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
    target_table: str,
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
    # parse_parameters stringifies every value, so a None (e.g. partition_hour
    # before the hourly cutover) must be omitted rather than sent as "None".
    base_parameters = {k: v for k, v in base_parameters.items() if v is not None}
    entry_point = entry_point if entry_point.endswith(".py") else f"{entry_point}.py"
    base_parameters = parse_parameters(base_parameters)
    return dag_execution_context.job_cluster_engine.create_spark_python_task(
        spark_job_path=f"{BASE_SPARK_JOB_PATH}{entry_point}",
        task_id=task_id,
        job_parameters=base_parameters,
        execution_timeout_hours=1,
    )


webhook_salesforce_api_v2 = CONFIG_SERVICE.get_config("webhook_salesforce_api_v2")
gchat_callback = GchatCallback(webhook_url_variable=webhook_salesforce_api_v2)

default_args = {
    "owner": "Data SS",
    "email_on_retry": False,
    "retries": 3,
    "depends_on_past": True,
    "on_failure_callback": gchat_callback.task_failure_alert,
}
with DAG(
    dag_id=DAG_ID,
    default_args=default_args,
    schedule_interval="0 * * * *",
    # Recent start_date on purpose: with the hourly schedule + catchup=True +
    # max_active_runs=1, an old start_date on a scheduler without prior runs
    # queues months of hourly backfill (~24 runs/day, one EMR cluster each).
    start_date=datetime(2026, 9, 15),
    catchup=True,
    tags=["SST", "SF", "salesforce", "api_v2"],
    on_failure_callback=gchat_callback.dag_failure_alert,
    max_active_runs=1,
) as dag:
    dag_execution_context = build_dag_execution_context(dag)

    start = SStPlaceholderOperator(task_id="start_salesforce_api_v2")
    end = SStPlaceholderOperator(task_id="end_salesforce_api_v2")

    execute_job_cluster = create_execute_job_cluster_task(dag_execution_context)
    start >> execute_job_cluster

    daily_objects_gate = ShortCircuitOperator(
        task_id="check-hour-to-run-daily-objects",
        python_callable=lambda hour: int(hour) == DAILY_EXECUTION_HOUR,
        op_args=["{{ data_interval_end.hour }}"],
        # False is load-bearing: the default (True) flat-skips every transitive
        # downstream — including terminate-emr-cluster and end — leaking a live
        # EMR cluster. With False only the direct daily raw tasks are skipped;
        # the skip propagates to their clean tasks via all_success, while
        # terminate (all_done) and end (none_failed_min_one_success) honor
        # their own trigger rules. Skipped also satisfies depends_on_past
        # (Airflow counts SKIPPED as a successful previous state), so the
        # default_args depends_on_past=True never deadlocks across hours.
        ignore_downstream_trigger_rules=False,
    )
    execute_job_cluster >> daily_objects_gate

    clean_tasks: List = []
    for object_table, object_conf in OBJECTS_CONFIG.items():
        api_entity = object_conf["api_entity"]
        # Per-object hourly cutover: hourly objects run every tick with
        # --partition_hour (strftime("%H") is always two digits) for the hour
        # they just completed. Daily objects (hourly false or absent) run only
        # behind the gate, without an hour (None is dropped from the job
        # parameters by create_sst_task) and with the completed previous day.
        is_hourly = object_conf.get("hourly", False)
        parameters = {
            "api_entity": api_entity,
            "endpoint": SALESFORCE_ENDPOINT,
        }
        clean_parameters = {
            "source_schema": RAW_SCHEMA,
            "sync_hive": "True",
        }
        if is_hourly:
            partition_hour = "{{ data_interval_start.strftime('%H') }}"
            parameters["partition_hour"] = partition_hour
            clean_parameters["partition_hour"] = partition_hour
        else:
            parameters["partition_date"] = DAILY_PARTITION_DATE
            clean_parameters["partition_date"] = DAILY_PARTITION_DATE

        raw_task = create_sst_task(
            dag_execution_context=dag_execution_context,
            target_schema=RAW_SCHEMA,
            target_table=object_table,
            entry_point="salesforce/api_v2",
            parameters=parameters,
        )

        clean_task = create_sst_task(
            dag_execution_context=dag_execution_context,
            target_schema=CLEAN_SCHEMA,
            target_table=object_table,
            entry_point="salesforce/api_v2_clean",
            parameters=clean_parameters,
        )

        DatasetAdder.attach_dataset_to_task(clean_task)

        if is_hourly:
            execute_job_cluster >> raw_task >> clean_task
        else:
            daily_objects_gate >> raw_task >> clean_task
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
