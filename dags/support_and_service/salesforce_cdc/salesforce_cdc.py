import math
import os
from copy import deepcopy
from datetime import datetime, timedelta
from typing import Dict

from airflow import DAG
from airflow.models.baseoperator import cross_downstream
from databricks_plugin import (
    QuintoAndarDatabricksCheckJobTaskOperator,
    QuintoAndarDatabricksExecuteJobClusterOperator,
)

from bietlejuice.base.airflow.datasets.dataset_adder import DatasetAdder
from bietlejuice.base.airflow.enums.storage_format_enum import StorageFormatEnum
from bietlejuice.base.jiraops.jiraops_callback import JiraOpsCallback
from bietlejuice.base.notification.gchat_callback import GchatCallback
from bietlejuice.base.sst.airflow.common.common import (
    get_cluster_config,
    get_libs,
    parse_parameters,
)
from bietlejuice.base.sst.airflow.common.configs import (
    DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)
from bietlejuice.base.sst.airflow.operators.base import SStPlaceholderOperator
from bietlejuice.services.configuration_service import ConfigurationService

# TODO: Move to only salesforce
DAG_NAME = "salesforce_cdc"
DAG_ID = f"bietlejuice.{DAG_NAME.replace('.', '_')}"
ENV = os.environ.get("ENVIRONMENT")
CONFIG_SERVICE = ConfigurationService(DAG_NAME)
DATABRICKS_CONN_ID = "databricks_new"
BIETLEJUICE_REPO_PATH = CONFIG_SERVICE.get_config("databricks_bietlejuice_repo_path")
BASE_SPARK_JOB_PATH = f"{BIETLEJUICE_REPO_PATH}/spark_jobs/sst_pipelines/"
RELATIVE_DAG_PATH = "dags/support_and_service/salesforce_cdc"
EVENTS_CONFIG = CONFIG_SERVICE.get_config("events_config")
SALESFORCE_ENDPOINT = CONFIG_SERVICE.get_config("salesforce_endpoint")
THRESHOLD_PARTITION_HOURS = CONFIG_SERVICE.get_config("threshold_partition_hours")
THRESHOLD_TIME_HOURS = CONFIG_SERVICE.get_config("threshold_time_hours")
# Observe-only by default: the contract writes to
# datalake_sst_metrics.contract_quality_checks but a violation must not fail the
# task, because the whole lineage (clean, DLQ, metrics) hangs off it and a stale
# hour would otherwise block every downstream hour via wait_for_downstream.
# Flip per event in *_conf.yml (``fail_on_quality_contract: true``) to enforce.
FAIL_ON_QUALITY_CONTRACT = CONFIG_SERVICE.get_config("fail_on_quality_contract")

# Use config and DAG constants so the DAG works without requiring Airflow Variables
# (bucket/dag_name/environment). Config is loaded per environment (forno_conf vs prod_conf).
bucket = CONFIG_SERVICE.get_config("datalake_bucket")


BASE_PARAMETERS = {
    "env": ENV,
    "dag_name": DAG_NAME,
    "bucket": bucket,
    "partition_date": "{{ data_interval_start | ds }}",
    "partition_hour": "{{ data_interval_start.strftime('%H') }}",
}


def lineage_pool_name(cluster_id: str) -> str:
    return f"salesforce_cdc_cluster_{cluster_id}"


def ensure_lineage_pool(cluster_id: str) -> str:
    """One Airflow pool slot = at most one hour executing this lineage."""
    from airflow.models.pool import Pool

    pool_name = lineage_pool_name(cluster_id)
    try:
        Pool.create_or_update_pool(
            name=pool_name,
            slots=1,
            description=(f"Serialize {DAG_ID} cluster {cluster_id} to one active hour"),
            include_deferred=False,
        )
    except Exception:
        # Dag-file parse in tests / without a metadata DB still assigns pool=.
        pass
    return pool_name


def create_sst_task(
    target_schema: str,
    target_table: str,
    entry_point: str,
    parameters: Dict[str, str],
    task_id: str = None,
    pool: str = None,
):

    task_id = f"load_{target_schema}_{target_table}" if not task_id else task_id
    base_parameters = {
        **BASE_PARAMETERS,
        "target_schema": target_schema,
        "target_table": target_table,
        "job_name": task_id,
        **parameters,
    }
    # override task_id if provided
    entry_point = entry_point if entry_point.endswith(".py") else f"{entry_point}.py"
    base_parameters = parse_parameters(base_parameters)
    return QuintoAndarDatabricksCheckJobTaskOperator(
        databricks_conn_id=DATABRICKS_CONN_ID,
        dag=dag,
        task_id=task_id,
        json={
            "spark_python_task": {
                "python_file": f"{BASE_SPARK_JOB_PATH}{entry_point}",
                "parameters": base_parameters,
            }
        },
        execution_timeout=timedelta(hours=1),
        depends_on_past=False,
        pool=pool,
    )


def create_execute_job_cluster_task(dag: DAG, cluster_id: str, task_id: str, pool: str):
    # The operator only disambiguates job names by the digits it finds in the
    # task_id, so digit-less lineages (case, email_message) would resolve to the
    # same Databricks job for a given hour and overwrite each other's task list.
    # get_cluster_config returns the shared ConfigurationService dict, hence the copy.
    cluster_configuration = deepcopy(get_cluster_config(CONFIG_SERVICE))
    cluster_configuration["cluster_name"] = f"{DAG_ID}_{{{{ run_id }}}}_{cluster_id}"
    return QuintoAndarDatabricksExecuteJobClusterOperator(
        databricks_conn_id="databricks_new",
        dag=dag,
        task_id=task_id,
        cluster_configuration=cluster_configuration,
        access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
        libraries=get_libs(ENV),
        pool=pool,
        # Do not start hour N+1's cluster until hour N's execute succeeded and
        # end_cdc_cluster_* (full lineage) succeeded. See execute >> end.
        depends_on_past=True,
        wait_for_downstream=True,
    )


def create_previous_lineage_gate(cluster_id: str, pool: str):
    return SStPlaceholderOperator(
        task_id=f"wait_previous_lineage_{cluster_id}",
        depends_on_past=True,
        wait_for_downstream=True,
        pool=pool,
    )


DEDICATED_CLUSTER_EVENTS = ("case", "email_message")
NUMBER_OF_POOLED_CLUSTERS = 2


# The lineage after the clean gate, declared as ordered stages: tasks inside a
# stage run in parallel, stages run in sequence. Adding a metric or moving the
# DLQ is a change here, not new wiring code.
#
# Every metric sits after the DLQ on purpose. ``quality/metrics/stability`` and
# ``quality/metrics/latency`` both iterate LAYERS = ["raw", "clean"], and the DLQ
# writes to both — it upserts recovered API records into raw and replays their
# CDC history into clean. Running the metrics alongside the DLQ would let them
# read a half-recovered partition, so their values would depend on task timing.
# Downstream of it, they consistently describe the post-recovery state.
POST_CLEAN_STAGES = (
    (
        dict(
            task_id="dlq_{table}",
            entry_point="salesforce/dlq",
            target_schema="datalake_salesforce_raw",
            event_parameters=("api_entity", "salesforce_endpoint"),
            emits_dataset=True,
        ),
    ),
    (
        dict(
            task_id="metrics_pipeline_stability_{table}",
            entry_point="quality/metrics/stability",
        ),
        dict(
            task_id="metrics_pipeline_latency_{table}",
            entry_point="quality/metrics/latency",
        ),
        dict(
            task_id="metrics_pipeline_missing_events_{table}",
            entry_point="salesforce/metrics/missing_events",
        ),
    ),
)


def build_stage_task(spec: Dict, event_table: str, event_parameters: Dict, pool: str):
    """Turn one POST_CLEAN_STAGES entry into a task via ``create_sst_task``."""
    task = create_sst_task(
        target_schema=spec.get("target_schema", ""),
        target_table=event_table,
        entry_point=spec["entry_point"],
        parameters={
            key: event_parameters[key] for key in spec.get("event_parameters", ())
        },
        task_id=spec["task_id"].format(table=event_table),
        pool=pool,
    )
    if spec.get("emits_dataset", False):
        # For downstream dataset-triggered DAGs. core_support_journey does NOT
        # use this: it gates on the task name via SStExternalTaskSensor, driven
        # by the ``tasks:`` list in its *_conf.yml.
        DatasetAdder.attach_dataset_to_task(task)
    return task


def wire_task_stages(
    stages, upstream, event_table: str, event_parameters: Dict, pool: str, end_cluster
):
    """Chain declarative stages between ``upstream`` and ``end_cluster``.

    Returns the tasks keyed by ``task_id`` so a caller can reach a specific one
    (e.g. to attach a dataset) without knowing the stage layout.
    """
    tasks_by_id = {}
    previous_stage = [upstream]
    for stage in stages:
        stage_tasks = [
            build_stage_task(spec, event_table, event_parameters, pool)
            for spec in stage
        ]
        # cross_downstream, not ``>>``: Airflow defines no ``>>`` between two
        # lists, so chaining a multi-task stage onto another would raise
        # TypeError at parse time.
        cross_downstream(previous_stage, stage_tasks)
        previous_stage = stage_tasks
        tasks_by_id.update({task.task_id: task for task in stage_tasks})
    previous_stage >> end_cluster
    return tasks_by_id


def wire_event_lineage(execute_job_cluster, event: str, end_cluster, pool: str):
    parameters = EVENTS_CONFIG[event]
    event_table = f"events_{event.lower()}"
    parameters["salesforce_endpoint"] = SALESFORCE_ENDPOINT
    threshold_time_hours = parameters.get("threshold_time_hours", THRESHOLD_TIME_HOURS)
    threshold_partition_hours = parameters.get(
        "threshold_partition_hours", THRESHOLD_PARTITION_HOURS
    )
    fail_on_violation = parameters.get(
        "fail_on_quality_contract", FAIL_ON_QUALITY_CONTRACT
    )

    raw_task = create_sst_task(
        target_schema="datalake_salesforce_raw",
        target_table=event_table,
        entry_point="salesforce/cdc_raw",
        parameters=parameters,
        pool=pool,
    )

    clean_task = create_sst_task(
        target_schema="datalake_salesforce_clean",
        target_table=event_table,
        entry_point="salesforce/cdc_clean",
        parameters={
            "source_schema": "datalake_salesforce_raw",
            "sync_hive": "True",
        },
        pool=pool,
    )
    if event == "case":
        clean_task.params.update(
            {
                "schema": "salesforce",
                "table_name": event_table,
                "layer": "clean",
                "bucket": bucket,
                "storage_format": StorageFormatEnum.PARQUET.value,
            }
        )
    # Clean still emits its own dataset for downstream consumers. Core Support
    # Journey's Case sensor now waits on ``dlq_events_case`` instead, so recovery
    # is already in clean before the core model reads it.
    DatasetAdder.attach_dataset_to_task(clean_task)

    if parameters.get("skip_quality_contracts", False):
        execute_job_cluster >> raw_task >> clean_task
        wire_task_stages(
            POST_CLEAN_STAGES,
            clean_task,
            event_table,
            parameters,
            pool,
            end_cluster,
        )
        return

    quality_contract_raw = create_sst_task(
        target_schema="datalake_salesforce_raw",
        target_table=event_table,
        entry_point="quality/contracts/generic",
        parameters={
            "threshold_time_hours": threshold_time_hours,
            "threshold_partition_hours": threshold_partition_hours,
            "fail_on_violation": fail_on_violation,
        },
        task_id=f"quality_contract_checks_raw_{event_table}",
        pool=pool,
    )
    quality_contract_clean = create_sst_task(
        target_schema="datalake_salesforce_clean",
        target_table=event_table,
        entry_point="quality/contracts/generic",
        parameters={
            "threshold_time_hours": threshold_time_hours,
            "threshold_partition_hours": threshold_partition_hours,
            "fail_on_violation": fail_on_violation,
        },
        task_id=f"quality_contract_checks_clean_{event_table}",
        pool=pool,
    )
    (
        execute_job_cluster
        >> raw_task
        >> quality_contract_raw
        >> clean_task
        >> quality_contract_clean
    )
    wire_task_stages(
        POST_CLEAN_STAGES,
        quality_contract_clean,
        event_table,
        parameters,
        pool,
        end_cluster,
    )


def build_cluster_lineage(cluster_id: str, events):
    if not events:
        return
    pool = ensure_lineage_pool(cluster_id)
    wait_previous_lineage = create_previous_lineage_gate(cluster_id, pool)
    execute_job_cluster = create_execute_job_cluster_task(
        dag=dag,
        cluster_id=cluster_id,
        task_id=f"execute_cdc_cluster_{cluster_id}",
        pool=pool,
    )
    end_cluster = SStPlaceholderOperator(
        task_id=f"end_cdc_cluster_{cluster_id}",
        depends_on_past=False,
        pool=pool,
    )
    wait_previous_lineage >> execute_job_cluster
    for event in events:
        wire_event_lineage(execute_job_cluster, event, end_cluster, pool)
    # Immediate downstream of the gate and execute includes the lineage leaf
    # so wait_for_downstream waits for the full hour, not only cluster start.
    wait_previous_lineage >> end_cluster
    execute_job_cluster >> end_cluster


jiraops_callback = JiraOpsCallback()
webhook_salesforce_cdc = CONFIG_SERVICE.get_config("webhook_salesforce_cdc")
gchat_callback = GchatCallback(webhook_url_variable=webhook_salesforce_cdc)

default_args = {
    "owner": "Data SS",
    "email_on_retry": False,
    "retries": 3,
    "depends_on_past": True,
    "on_failure_callback": gchat_callback.task_failure_alert,
    # TODO: Uncomment callback when the dag is ready with all events and quality checks are implemented
    # "on_failure_callback": jiraops_callback.task_failure_alert,
}
with DAG(
    dag_id=DAG_ID,
    default_args=default_args,
    schedule_interval="0 * * * *",
    start_date=datetime(2026, 3, 12),
    catchup=True,
    tags=[
        "SST",
        "SF",
        "salesforce",
        "criticality:High",
        "sla_deadline_localtime:08:00",
    ],
    on_failure_callback=gchat_callback.dag_failure_alert,
    # TODO: Uncomment callback when the dag is ready with all events and quality checks are implemented
    # on_failure_callback=jiraops_callback.dag_failure_alert,
    # Independent cluster lineages (case, email_message, pooled events) should
    # not block each other across hours via a shared start/end. 24 open hours
    # keeps Case/Email moving if a pooled lineage lags up to a day.
    max_active_runs=24,
) as dag:
    dedicated_events = [
        event for event in DEDICATED_CLUSTER_EVENTS if event in EVENTS_CONFIG
    ]
    pooled_events = [
        event for event in EVENTS_CONFIG if event not in DEDICATED_CLUSTER_EVENTS
    ]

    for event in dedicated_events:
        build_cluster_lineage(event, [event])

    if pooled_events:
        pool_max_size = math.ceil(len(pooled_events) / NUMBER_OF_POOLED_CLUSTERS) or 1
        job_pool = [
            pooled_events[i : i + pool_max_size]
            for i in range(0, len(pooled_events), pool_max_size)
        ]
        for i, pool_events in enumerate(job_pool):
            build_cluster_lineage(str(i), pool_events)
