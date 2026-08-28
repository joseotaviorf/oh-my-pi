"""
airflow parsing enforcement

Note: this line above forces Airflow to parse this file for implemented DAGs
"""

import math
import os
from copy import deepcopy
from datetime import datetime, timedelta
from os.path import basename, dirname
from typing import Dict

from airflow import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCheckJobTaskOperator,
    QuintoAndarDatabricksExecuteJobClusterOperator,
)

from bietlejuice.base.airflow.cluster_config_resolver import merge_cluster_configuration
from bietlejuice.base.airflow.datasets.dataset_adder import DatasetAdder
from bietlejuice.base.jiraops.jiraops_callback import JiraOpsCallback
from bietlejuice.base.notification.gchat_callback import GchatCallback
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.sst.airflow.common.common import get_libs, parse_parameters
from bietlejuice.base.sst.airflow.common.configs import (
    DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
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

# Load cluster definition from salesforce_for_sale_cluster.yml.
# merge_cluster_configuration resolves the cluster type to its full hardware specs
# (node_type_id, spark_version, etc.) stored in ConfigurationService, then deep-merges
# the custom_configurations overrides on top.
# ClusterEnvVarsHelper.input_spark_env_vars injects SPARK_VERSION, INMETRO_VERSION and
# DEEQU_JAR_VERSION into spark_env_vars so Spark jobs load the correct library versions.
_cluster_file_path = DAGPackagesPathService.resolve_artifact_file_path(
    artifact_type="dag_cluster", dag_name=DAG_NAME
)
_cluster_args = FileService.get_dict_from_yaml_file(_cluster_file_path)["cluster"]
DATABRICKS_CONN_ID = _cluster_args["databricks_conn_id"]
CLUSTER_CONFIGURATION = merge_cluster_configuration(_cluster_args, CONFIG_SERVICE)

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
        execution_timeout=timedelta(minutes=30),
        depends_on_past=False,
        pool=pool,
    )


def create_execute_job_cluster_task(dag: DAG, cluster_id: str, task_id: str, pool: str):
    cluster_configuration = deepcopy(CLUSTER_CONFIGURATION)
    cluster_configuration["cluster_name"] = f"{DAG_ID}_{{{{ run_id }}}}_{cluster_id}"
    return QuintoAndarDatabricksExecuteJobClusterOperator(
        databricks_conn_id=DATABRICKS_CONN_ID,
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


def build_metrics_tasks(event_table, pool: str):
    return [
        create_sst_task(
            target_schema="",
            target_table=event_table,
            entry_point="quality/metrics/stability",
            parameters={},
            task_id=f"metrics_pipeline_stability_{event_table}",
            pool=pool,
        ),
        create_sst_task(
            target_schema="",
            target_table=event_table,
            entry_point="quality/metrics/latency",
            parameters={},
            task_id=f"metrics_pipeline_latency_{event_table}",
            pool=pool,
        ),
        create_sst_task(
            target_schema="",
            target_table=event_table,
            entry_point="salesforce/metrics/missing_events",
            parameters={},
            task_id=f"metrics_pipeline_missing_events_{event_table}",
            pool=pool,
        ),
    ]


def wire_event_lineage(execute_job_cluster, event: str, end_cluster, pool: str):
    parameters = EVENTS_CONFIG[event]
    event_table = f"events_{event.lower()}"
    threshold_time_hours = parameters.get("threshold_time_hours", 24)

    raw_task = create_sst_task(
        target_schema=RAW_SCHEMA,
        target_table=event_table,
        entry_point="salesforce/cdc_raw",
        parameters=parameters,
        pool=pool,
    )

    clean_task = create_sst_task(
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

    metrics_tasks = build_metrics_tasks(event_table, pool)
    if parameters.get("skip_quality_contracts", False):
        (execute_job_cluster >> raw_task >> clean_task >> metrics_tasks >> end_cluster)
        return

    quality_contract_raw = create_sst_task(
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
    "owner": CONFIG_SERVICE.get_config("owner"),
    "email_on_retry": False,
    "retries": 1,
    "depends_on_past": True,
    "on_failure_callback": gchat_callback.task_failure_alert,
    # TODO: Uncomment callback when the dag is ready with all events and quality checks are implemented
    # "on_failure_callback": jiraops_callback.task_failure_alert,
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
    # TODO: Uncomment callback when the dag is ready with all events and quality checks are implemented
    # on_failure_callback=jiraops_callback.dag_failure_alert,
    # Single cluster lineage: keep one active hour. Sequencing across hours is
    # the pool (1 slot) plus wait_previous_lineage / execute wait_for_downstream,
    # not depends_on_past on the load tasks.
    max_active_runs=1,
) as dag:
    NUMBER_OF_CLUSTERS = 1
    events_lst = list(EVENTS_CONFIG.keys())
    pool_max_size = math.ceil(len(events_lst) / NUMBER_OF_CLUSTERS) or 1
    job_pool = [
        events_lst[i : i + pool_max_size]
        for i in range(0, len(events_lst), pool_max_size)
    ]
    for i, pool_events in enumerate(job_pool):
        build_cluster_lineage(str(i), pool_events)
