import math
import os
from datetime import datetime
from typing import Dict, List, Optional

from airflow import DAG
from airflow.models.baseoperator import BaseOperator
from airflow.operators.python import PythonOperator

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
from bietlejuice.base.jiraops.jiraops_callback import JiraOpsCallback
from bietlejuice.base.notification.gchat_callback import GchatCallback
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.sst.airflow.common.common import parse_parameters
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.file_service import FileService

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
_cluster_file_path = DAGPackagesPathService.resolve_artifact_file_path(
    artifact_type="dag_cluster", dag_name=DAG_NAME
)
CLUSTER_ARGS = FileService.get_dict_from_yaml_file(_cluster_file_path)["cluster"]

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


def create_execute_job_cluster_task(
    dag_execution_context: DagExecutionContext,
    execute_job_cluster_local_id: Optional[int] = None,
) -> BaseOperator:
    return dag_execution_context.job_cluster_engine.create_execute_cluster_task(
        config_service=CONFIG_SERVICE,
        minimum_cluster_runtime_version=None,
        execute_job_cluster_local_id=execute_job_cluster_local_id,
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
    entry_point = entry_point if entry_point.endswith(".py") else f"{entry_point}.py"
    base_parameters = parse_parameters(base_parameters)
    return dag_execution_context.job_cluster_engine.create_spark_python_task(
        spark_job_path=f"{BASE_SPARK_JOB_PATH}{entry_point}",
        task_id=task_id,
        job_parameters=base_parameters,
        execution_timeout_hours=1,
    )


def build_metrics_tasks(
    dag_execution_context: DagExecutionContext,
    event_table: str,
) -> List[BaseOperator]:
    return [
        create_sst_task(
            dag_execution_context=dag_execution_context,
            target_schema="",
            target_table=event_table,
            entry_point="quality/metrics/stability",
            parameters={},
            task_id=f"metrics_pipeline_stability_{event_table}",
        ),
        create_sst_task(
            dag_execution_context=dag_execution_context,
            target_schema="",
            target_table=event_table,
            entry_point="quality/metrics/latency",
            parameters={},
            task_id=f"metrics_pipeline_latency_{event_table}",
        ),
        create_sst_task(
            dag_execution_context=dag_execution_context,
            target_schema="",
            target_table=event_table,
            entry_point="salesforce/metrics/missing_events",
            parameters={},
            task_id=f"metrics_pipeline_missing_events_{event_table}",
        ),
    ]


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
    dag_execution_context = build_dag_execution_context(dag)

    job_cluster_finished = PythonOperator(
        task_id="job-cluster-finished",
        python_callable=lambda: None,
        dag=dag,
    )

    NUMBER_OF_CLUSTERS = 2
    events_lst = list(EVENTS_CONFIG.keys())
    pool_max_size = math.ceil(len(events_lst) / NUMBER_OF_CLUSTERS) or 1
    job_pool = [
        events_lst[i : i + pool_max_size]
        for i in range(0, len(events_lst), pool_max_size)
    ]

    for i, pool_events in enumerate(job_pool):
        execute_job_cluster_local_id = i + 1
        local_id_param = (
            execute_job_cluster_local_id if execute_job_cluster_local_id > 1 else None
        )
        execute_job_cluster = create_execute_job_cluster_task(
            dag_execution_context,
            execute_job_cluster_local_id=local_id_param,
        )
        cluster_completion_sink = get_job_cluster_completion_sink(
            dag_execution_context,
            execute_job_cluster,
            job_cluster_finished,
            execute_job_cluster_local_id=local_id_param,
        )
        pool_work_tasks: List[BaseOperator] = []

        for event in pool_events:
            parameters = EVENTS_CONFIG[event]
            event_table = f"events_{event.lower()}"
            parameters["salesforce_endpoint"] = SALESFORCE_ENDPOINT
            threshold_time_hours = parameters.get(
                "threshold_time_hours", THRESHOLD_TIME_HOURS
            )
            threshold_partition_hours = parameters.get(
                "threshold_partition_hours", THRESHOLD_PARTITION_HOURS
            )

            raw_task = create_sst_task(
                dag_execution_context=dag_execution_context,
                target_schema="datalake_salesforce_raw",
                target_table=event_table,
                entry_point="salesforce/cdc_raw",
                parameters=parameters,
            )

            clean_task = create_sst_task(
                dag_execution_context=dag_execution_context,
                target_schema="datalake_salesforce_clean",
                target_table=event_table,
                entry_point="salesforce/cdc_clean",
                parameters={
                    "source_schema": "datalake_salesforce_raw",
                    "sync_hive": "True",
                },
            )
            # Emit a per-table dataset event for the clean layer so downstream
            # DAGs can trigger on this DAG via dependencies.yaml.
            DatasetAdder.attach_dataset_to_task(clean_task)

            metrics_tasks = build_metrics_tasks(dag_execution_context, event_table)
            pool_work_tasks.extend(metrics_tasks)
            if parameters.get("skip_quality_contracts", False):
                execute_job_cluster >> raw_task >> clean_task >> metrics_tasks
            else:
                quality_contract_raw = create_sst_task(
                    dag_execution_context=dag_execution_context,
                    target_schema="datalake_salesforce_raw",
                    target_table=event_table,
                    entry_point="quality/contracts/generic",
                    parameters={
                        "threshold_time_hours": threshold_time_hours,
                        "threshold_partition_hours": threshold_partition_hours,
                    },
                    task_id=f"quality_contract_checks_raw_{event_table}",
                )
                quality_contract_clean = create_sst_task(
                    dag_execution_context=dag_execution_context,
                    target_schema="datalake_salesforce_clean",
                    target_table=event_table,
                    entry_point="quality/contracts/generic",
                    parameters={
                        "threshold_time_hours": threshold_time_hours,
                        "threshold_partition_hours": threshold_partition_hours,
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
                )

            for metric_task in metrics_tasks:
                metric_task >> cluster_completion_sink

        attach_emr_job_cluster_finished_work_prerequisites(
            dag_execution_context,
            job_cluster_finished_task=job_cluster_finished,
            work_completion_tasks=pool_work_tasks,
        )
        attach_emr_terminate_cluster_work_prerequisites(
            dag_execution_context,
            cluster_completion_sink,
            execute_job_cluster_task=execute_job_cluster,
            job_cluster_finished_task=job_cluster_finished,
        )
