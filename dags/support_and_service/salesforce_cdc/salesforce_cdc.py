import math
import os
from datetime import datetime, timedelta
from typing import Dict

from airflow import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCheckJobTaskOperator,
    QuintoAndarDatabricksExecuteJobClusterOperator,
)

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


def create_sst_task(
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
    )


def create_execute_job_cluster_task(dag: DAG, task_id: str):
    return QuintoAndarDatabricksExecuteJobClusterOperator(
        databricks_conn_id="databricks_new",
        dag=dag,
        task_id=task_id,
        cluster_configuration=get_cluster_config(CONFIG_SERVICE),
        access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
        libraries=get_libs(ENV),
    )


def build_metrics_tasks(event_table):

    return [
        create_sst_task(
            target_schema="",
            target_table=event_table,
            entry_point="quality/metrics/stability",
            parameters={},
            task_id=f"metrics_pipeline_stability_{event_table}",
        ),
        create_sst_task(
            target_schema="",
            target_table=event_table,
            entry_point="quality/metrics/latency",
            parameters={},
            task_id=f"metrics_pipeline_latency_{event_table}",
        ),
        create_sst_task(
            target_schema="",
            target_table=event_table,
            entry_point="salesforce/metrics/missing_events",
            parameters={},
            task_id=f"metrics_pipeline_missing_events_{event_table}",
        ),
    ]


def create_start_end_operator(task_id: str):

    start = SStPlaceholderOperator(task_id=f"start_{task_id}")
    end = SStPlaceholderOperator(task_id=f"end_{task_id}")
    return start, end


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
    tags=["SST", "SF", "salesforce"],  # better formatting
    on_failure_callback=gchat_callback.dag_failure_alert,
    # TODO: Uncomment callback when the dag is ready with all events and quality checks are implemented
    # on_failure_callback=jiraops_callback.dag_failure_alert,
    max_active_runs=1,
) as dag:
    start, end = create_start_end_operator("salesforce")

    NUMBER_OF_CLUSTERS = 2
    events_lst = list(EVENTS_CONFIG.keys())
    pool_max_size = math.ceil(len(events_lst) / NUMBER_OF_CLUSTERS) or 1
    job_pool = [
        events_lst[i : i + pool_max_size]
        for i in range(0, len(events_lst), pool_max_size)
    ]

    execute_job_clusters = []
    for i, pool_events in enumerate(job_pool):
        execute_job_cluster = create_execute_job_cluster_task(
            dag=dag, task_id=f"execute_cdc_cluster_{i}"
        )
        execute_job_clusters.append(execute_job_cluster)
        end_pool = SStPlaceholderOperator(task_id=f"end_pool_{i}")

        for event in pool_events:
            parameters = EVENTS_CONFIG[event]
            event_table = f"events_{event.lower()}"
            threshold_time_hours = parameters.get("threshold_time_hours", 24)

            raw_task = create_sst_task(
                target_schema="datalake_salesforce_raw",
                target_table=event_table,
                entry_point="salesforce/cdc_raw",
                parameters=parameters,
            )

            clean_task = create_sst_task(
                target_schema="datalake_salesforce_clean",
                target_table=event_table,
                entry_point="salesforce/cdc_clean",
                parameters={
                    "source_schema": "datalake_salesforce_raw",
                    "sync_hive": "True",
                },
            )

            metrics_tasks = build_metrics_tasks(event_table)
            if parameters.get("skip_quality_contracts", False):
                (
                    execute_job_cluster
                    >> raw_task
                    >> clean_task
                    >> metrics_tasks
                    >> end_pool
                    >> end
                )
            else:
                quality_contract_raw = create_sst_task(
                    target_schema="datalake_salesforce_raw",
                    target_table=event_table,
                    entry_point="quality/contracts/generic",
                    parameters={
                        "threshold_time_hours": threshold_time_hours,
                    },
                    task_id=f"quality_contract_checks_raw_{event_table}",
                )
                quality_contract_clean = create_sst_task(
                    target_schema="datalake_salesforce_clean",
                    target_table=event_table,
                    entry_point="quality/contracts/generic",
                    parameters={
                        "threshold_time_hours": threshold_time_hours,
                    },
                    task_id=f"quality_contract_checks_clean_{event_table}",
                )
                (
                    execute_job_cluster
                    >> raw_task
                    >> quality_contract_raw
                    >> clean_task
                    >> quality_contract_clean
                    >> metrics_tasks
                    >> end_pool
                    >> end
                )

    start >> execute_job_clusters
