"""
airflow parsing enforcement

Note: this line above forces Airflow to parse this file for implemented DAGs
"""

import math
import os
from datetime import datetime, timedelta
from os.path import basename, dirname
from typing import Dict, List

from airflow import DAG

from bietlejuice.base.airflow.datasets.dataset_adder import DatasetAdder
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.notification.gchat_callback import GchatCallback
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.sst.airflow.common.common import parse_parameters
from bietlejuice.base.sst.airflow.common.emr_dag_kit import (
    build_dag_execution_context,
    create_execute_cluster_task,
    emr_execute_cluster_local_id,
    finalize_emr_pipeline,
)
from bietlejuice.base.sst.airflow.operators.base import SStPlaceholderOperator
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.file_service import FileService

DAG_NAME = basename(dirname(__file__))
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
CONFIG_SERVICE = ConfigurationService(DAG_NAME)
BIETLEJUICE_REPO_PATH = CONFIG_SERVICE.get_config("databricks_bietlejuice_repo_path")
BASE_SPARK_JOB_PATH = f"{BIETLEJUICE_REPO_PATH}/spark_jobs/sst_pipelines/"
EVENTS_CONFIG = CONFIG_SERVICE.get_config("events_config")

# Use config and DAG constants so the DAG works without requiring Airflow Variables
# (bucket/dag_name/environment). Config is loaded per environment (forno_conf vs prod_conf).
bucket = CONFIG_SERVICE.get_config("datalake_bucket")
RAW_SCHEMA = CONFIG_SERVICE.get_config("raw_schema")
CLEAN_SCHEMA = CONFIG_SERVICE.get_config("clean_schema")
# cdc_raw falls back to a Salesforce REST recovery when AppFlow has not delivered
# the partition hour, and that path needs the endpoint. Same wiring as salesforce_cdc.
SALESFORCE_ENDPOINT = CONFIG_SERVICE.get_config("salesforce_endpoint")
# AppFlow APIs are account-scoped: on EMR prod the cluster runs in the data
# account while the flows live in prod, so cdc_raw has to assume a role for the
# AppFlow client. Empty in forno, where emr-forno already sees its own flows.
APPFLOW_ASSUME_ROLE_ARN = CONFIG_SERVICE.get_config("appflow_assume_role_arn")
# Sent only when set: EMR's command-runner.jar silently discards empty-string
# step arguments, which would leave argparse with an orphan flag (AEFR-7513).
APPFLOW_PARAMETERS = (
    {"appflow_assume_role_arn": APPFLOW_ASSUME_ROLE_ARN}
    if APPFLOW_ASSUME_ROLE_ARN
    else {}
)

# Load cluster definition from salesforce_for_sale_cluster.yml. Its `type` is an
# emr_* preset, which is what routes this DAG to the EMR job cluster engine; the
# engine resolves the preset to full hardware specs and merges custom_configurations.
_cluster_file_path = DAGPackagesPathService.resolve_artifact_file_path(
    artifact_type="dag_cluster", dag_name=DAG_NAME
)
CLUSTER_ARGS = FileService.get_dict_from_yaml_file(_cluster_file_path)["cluster"]

BASE_PARAMETERS = {
    "env": ENV,
    "dag_name": DAG_NAME,
    "bucket": bucket,
    "partition_date": "{{ data_interval_start | ds }}",
    "partition_hour": "{{ data_interval_start.strftime('%H') }}",
}


def lineage_pool_name(cluster_id: str) -> str:
    return f"salesforce_for_sale_cluster_{cluster_id}"


def ensure_lineage_pool(cluster_id: str) -> str:
    """One Airflow pool slot = at most one Spark step executing this lineage."""
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
    dag_execution_context: DagExecutionContext,
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
    # execution_timeout_hours is an int contract, so the old 30-minute bound is not
    # representable; dagrun_timeout (3h) remains the real backstop.
    return dag_execution_context.job_cluster_engine.create_spark_python_task(
        spark_job_path=f"{BASE_SPARK_JOB_PATH}{entry_point}",
        task_id=task_id,
        job_parameters=base_parameters,
        execution_timeout_hours=1,
        pool=pool,
    )


def create_previous_lineage_gate(cluster_id: str, pool: str):
    # depends_on_past / wait_for_downstream are set here rather than in default_args:
    # default_args would also land on the engine-created cluster, step and terminate
    # tasks, and depends_on_past on terminate wedges the DAG permanently when one
    # hour's teardown does not succeed.
    return SStPlaceholderOperator(
        task_id=f"wait_previous_lineage_{cluster_id}",
        depends_on_past=True,
        wait_for_downstream=True,
        pool=pool,
    )


def build_metrics_tasks(
    dag_execution_context: DagExecutionContext, event_table, pool: str
):
    return [
        create_sst_task(
            dag_execution_context=dag_execution_context,
            target_schema="",
            target_table=event_table,
            entry_point="quality/metrics/stability",
            parameters={},
            task_id=f"metrics_pipeline_stability_{event_table}",
            pool=pool,
        ),
        create_sst_task(
            dag_execution_context=dag_execution_context,
            target_schema="",
            target_table=event_table,
            entry_point="quality/metrics/latency",
            parameters={},
            task_id=f"metrics_pipeline_latency_{event_table}",
            pool=pool,
        ),
        create_sst_task(
            dag_execution_context=dag_execution_context,
            target_schema="",
            target_table=event_table,
            entry_point="salesforce/metrics/missing_events",
            parameters={},
            task_id=f"metrics_pipeline_missing_events_{event_table}",
            pool=pool,
        ),
    ]


def wire_event_lineage(
    dag_execution_context: DagExecutionContext,
    execute_job_cluster,
    event: str,
    end_cluster,
    pool: str,
) -> List:
    """Wire one event's raw -> clean -> metrics chain. Returns the leaf tasks."""
    parameters = EVENTS_CONFIG[event]
    event_table = f"events_{event.lower()}"
    threshold_time_hours = parameters.get("threshold_time_hours", 24)

    raw_task = create_sst_task(
        dag_execution_context=dag_execution_context,
        target_schema=RAW_SCHEMA,
        target_table=event_table,
        entry_point="salesforce/cdc_raw",
        # Spread rather than mutate: EVENTS_CONFIG comes from the cached
        # ConfigurationService instance and is shared across events.
        parameters={
            **parameters,
            "salesforce_endpoint": SALESFORCE_ENDPOINT,
            **APPFLOW_PARAMETERS,
        },
        pool=pool,
    )

    clean_task = create_sst_task(
        dag_execution_context=dag_execution_context,
        target_schema=CLEAN_SCHEMA,
        target_table=event_table,
        entry_point="salesforce/cdc_clean",
        parameters={
            "source_schema": RAW_SCHEMA,
            "sync_hive": "True",
        },
        pool=pool,
    )
    DatasetAdder.attach_dataset_to_task(clean_task)

    metrics_tasks = build_metrics_tasks(dag_execution_context, event_table, pool)
    if parameters.get("skip_quality_contracts", False):
        (execute_job_cluster >> raw_task >> clean_task >> metrics_tasks >> end_cluster)
        return metrics_tasks

    quality_contract_raw = create_sst_task(
        dag_execution_context=dag_execution_context,
        target_schema=RAW_SCHEMA,
        target_table=event_table,
        entry_point="quality/contracts/generic",
        parameters={
            "threshold_time_hours": threshold_time_hours,
        },
        task_id=f"quality_contract_checks_raw_{event_table}",
        pool=pool,
    )
    quality_contract_clean = create_sst_task(
        dag_execution_context=dag_execution_context,
        target_schema=CLEAN_SCHEMA,
        target_table=event_table,
        entry_point="quality/contracts/generic",
        parameters={
            "threshold_time_hours": threshold_time_hours,
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
        >> metrics_tasks
        >> end_cluster
    )
    return metrics_tasks


def build_cluster_lineage(
    dag_execution_context: DagExecutionContext, shard_index: int, events
):
    if not events:
        return
    # Pool and end-task names stay 0-based to preserve existing task history and the
    # astro/local_pools.json entry; the engine-side task ids use the shifted local id.
    cluster_id = str(shard_index)
    pool = ensure_lineage_pool(cluster_id)
    wait_previous_lineage = create_previous_lineage_gate(cluster_id, pool)
    execute_job_cluster_local_id = emr_execute_cluster_local_id(shard_index)
    execute_job_cluster = create_execute_cluster_task(
        dag_execution_context,
        CONFIG_SERVICE,
        execute_job_cluster_local_id,
    )
    end_cluster = SStPlaceholderOperator(
        task_id=f"end_cdc_cluster_{cluster_id}",
        depends_on_past=False,
        pool=pool,
    )
    wait_previous_lineage >> execute_job_cluster
    leaf_tasks = [
        task
        for event in events
        for task in wire_event_lineage(
            dag_execution_context, execute_job_cluster, event, end_cluster, pool
        )
    ]
    # SOLE cross-hour guarantee: the gate's wait_for_downstream inspects only its
    # immediate downstreams, and end_cdc_cluster_* succeeds only once every step and
    # terminate-emr-cluster have succeeded. Do not remove this edge -- nothing tests it.
    # Nothing may be wired downstream of end_cdc_cluster_*: finalize_emr_pipeline walks
    # the graph from the cluster task and would turn that into a cycle.
    wait_previous_lineage >> end_cluster
    finalize_emr_pipeline(
        dag_execution_context,
        execute_job_cluster,
        leaf_tasks,
        end_cluster,
        execute_job_cluster_local_id,
    )


webhook_salesforce_cdc = CONFIG_SERVICE.get_config("webhook_salesforce_cdc")
gchat_callback = GchatCallback(webhook_url_variable=webhook_salesforce_cdc)

# depends_on_past is deliberately NOT here: it would propagate to the engine-created
# cluster, step and terminate tasks. It lives on wait_previous_lineage_* instead.
default_args = {
    "owner": CONFIG_SERVICE.get_config("owner"),
    "email_on_retry": False,
    "retries": 1,
    "on_failure_callback": gchat_callback.task_failure_alert,
}
with DAG(
    dag_id=DAG_ID,
    default_args=default_args,
    schedule_interval="0 * * * *",
    start_date=datetime(2026, 6, 8),
    dagrun_timeout=timedelta(hours=3),
    catchup=True,
    tags=["ForSale", "SF", "salesforce"],
    on_failure_callback=gchat_callback.dag_failure_alert,
    # Single cluster lineage: keep one active hour. Sequencing across hours is
    # the pool (1 slot) plus wait_previous_lineage / gate wait_for_downstream,
    # not depends_on_past on the load tasks.
    max_active_runs=1,
) as dag:
    dag_execution_context = build_dag_execution_context(
        dag,
        ENV,
        bucket,
        BASE_SPARK_JOB_PATH,
        CLUSTER_ARGS,
        CONFIG_SERVICE,
    )

    NUMBER_OF_CLUSTERS = 1
    events_lst = list(EVENTS_CONFIG.keys())
    pool_max_size = math.ceil(len(events_lst) / NUMBER_OF_CLUSTERS) or 1
    job_pool = [
        events_lst[i : i + pool_max_size]
        for i in range(0, len(events_lst), pool_max_size)
    ]
    # One shard at a time: the engine tracks a single "active" cluster task id, so a
    # shard's steps must all be created before the next shard's cluster.
    for i, pool_events in enumerate(job_pool):
        build_cluster_lineage(dag_execution_context, i, pool_events)
