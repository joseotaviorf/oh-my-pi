import os
from datetime import datetime, timedelta
from functools import partial
from pathlib import Path
from typing import Any, Dict, List, Tuple

import yaml
from airflow import DAG
from airflow.decorators import task_group
from airflow.models.baseoperator import BaseOperator

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
from bietlejuice.base.sst.airflow.operators.sensors import SStExternalTaskSensor
from bietlejuice.services.configuration_service import ConfigurationService

DAG_NAME = "core_support_journey"
DAG_ID = f"bietlejuice.{DAG_NAME.replace('.', '_')}"
ENV = os.environ.get("ENVIRONMENT")
CONFIG_SERVICE = ConfigurationService(DAG_NAME)
DATABRICKS_CONN_ID = "databricks_new"
BIETLEJUICE_REPO_PATH = CONFIG_SERVICE.get_config("databricks_bietlejuice_repo_path")
BASE_SPARK_JOB_PATH = f"{BIETLEJUICE_REPO_PATH}/spark_jobs/sst_pipelines/"
bucket = CONFIG_SERVICE.get_config("datalake_bucket")
CORE_SCHEMA = "core_support_journey"
CLUSTER_ARGS = CONFIG_SERVICE.get_config("cluster")
EXTERNAL_SENSOR_SPECS: Dict[str, List[str]] = CONFIG_SERVICE.get_config("dependencies")
TABLES_DIR = Path(__file__).resolve().parent / "tables"

gchat_webhook_var = CONFIG_SERVICE.get_config("webhook_salesforce_cdc")
gchat_callback = GchatCallback(webhook_url_variable=gchat_webhook_var)


def list_table_specs_from_dir(tables_dir: Path) -> List[Tuple[str, Dict[str, Any]]]:
    """
    Load every ``*.yml`` in ``tables_dir`` and return (table_stem, spec_dict) sorted by stem.
    """
    if not tables_dir.is_dir():
        raise ValueError(f"Tables directory {tables_dir} does not exist")
    out: List[Tuple[str, Dict[str, Any]]] = []
    for path in sorted(tables_dir.glob("*.yml")):
        with open(path, encoding="utf-8") as handle:
            loaded = yaml.safe_load(handle) or {}
        out.append((path.stem, loaded))
    return out


def get_daily_target_logical_date(
    logical_date: datetime, execution_hour: int
) -> datetime:
    """
    Map this hourly DAG's ``logical_date`` to the daily upstream run's ``logical_date``.

    The upstream lands ``d-1``'s data at ``execution_hour`` UTC, so its logical_date
    sits at that hour. We point at the latest upstream run that has already completed:

        2026-06-23 03:00:00 -> 2026-06-22 03:00:00   (at/after the cutoff -> d-1)
        2026-06-23 02:00:00 -> 2026-06-21 03:00:00   (in the 00:00..cutoff gap -> d-2)
    """
    target = logical_date.replace(
        hour=execution_hour, minute=0, second=0, microsecond=0
    )

    # In the gap between midnight and ``execution_hour`` the d-1 upstream run has
    # not landed yet, so fall back one extra day.
    days_back = 2 if logical_date.hour < execution_hour else 1

    return target - timedelta(days=days_back)


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
) -> BaseOperator:
    return dag_execution_context.job_cluster_engine.create_execute_cluster_task(
        config_service=CONFIG_SERVICE,
        minimum_cluster_runtime_version=None,
        execute_job_cluster_local_id=None,
    )


def table_config_relative_path(table_stem: str) -> str:
    """
    Path relative to the Astro DAG bundle prefix (``astronomer/dags/`` on artifacts S3).
    """
    dag_dir = Path(__file__).resolve().parent
    parts = dag_dir.parts
    dags_idx = parts.index("dags")
    dag_package_path = "/".join(parts[dags_idx + 1 :])
    return f"{dag_package_path}/tables/{table_stem}.yml"


def create_load_table_task(
    dag_execution_context: DagExecutionContext, table_stem: str
) -> BaseOperator:
    base_parameters = {
        **BASE_PARAMETERS,
        "target_schema": CORE_SCHEMA,
        "target_table": table_stem,
        "job_name": f"load_core_support_journey_{table_stem}",
        "table_config_relative_path": table_config_relative_path(table_stem),
    }
    base_parameters = parse_parameters(base_parameters)
    return dag_execution_context.job_cluster_engine.create_spark_python_task(
        spark_job_path=(
            f"{BASE_SPARK_JOB_PATH}core_model/support_journey/{table_stem}.py"
        ),
        task_id=f"load_core_support_journey_{table_stem}",
        job_parameters=base_parameters,
        execution_timeout_hours=2,
    )


@task_group(group_id="start_sensors")
def external_sensors():
    for external_dag_id, config in EXTERNAL_SENSOR_SPECS.items():
        for task_id in config["tasks"]:
            execution_date_fn = (
                partial(
                    get_daily_target_logical_date,
                    execution_hour=config["execution_hour"],
                )
                if config["is_daily"]
                else None
            )
            SStExternalTaskSensor(
                task_id=f"sensor_{external_dag_id.replace('.', '_')}_{task_id}",
                external_dag_id=external_dag_id,
                external_task_id=task_id,
                execution_date_fn=execution_date_fn,
            )


_DEFAULT_ARGS = {
    "owner": "Data SS",
    "email_on_retry": False,
    "retries": 3,
    "depends_on_past": True,
}

with DAG(
    dag_id=DAG_ID,
    default_args=_DEFAULT_ARGS,
    schedule_interval="0 * * * *",
    start_date=datetime(2026, 5, 1),
    catchup=True,
    tags=["core_model", "support_journey", "SST", "Salesforce", "SF"],
    max_active_runs=1,
    on_failure_callback=gchat_callback.dag_failure_alert,
) as dag:
    dag_execution_context = build_dag_execution_context(dag)

    start = SStPlaceholderOperator(task_id="start")
    end = SStPlaceholderOperator(task_id="end")
    execute_job_cluster = create_execute_job_cluster_task(dag_execution_context)

    # external_sensors = external_sensors()

    load_tasks = []
    for stem, _spec in list_table_specs_from_dir(TABLES_DIR):
        load_task = create_load_table_task(dag_execution_context, stem)
        # Emit a per-table dataset event so downstream DAGs (e.g. dw_support_journey)
        # can trigger on this DAG via dependencies.yaml.
        DatasetAdder.attach_dataset_to_task(load_task)
        load_tasks.append(load_task)

    cluster_completion_sink = get_job_cluster_completion_sink(
        dag_execution_context, execute_job_cluster, end
    )
    attach_emr_job_cluster_finished_work_prerequisites(
        dag_execution_context,
        job_cluster_finished_task=end,
        work_completion_tasks=load_tasks,
    )

    (
        start
        # >> external_sensors
        >> execute_job_cluster
        >> load_tasks
        >> cluster_completion_sink
    )
    attach_emr_terminate_cluster_work_prerequisites(
        dag_execution_context,
        cluster_completion_sink,
        execute_job_cluster_task=execute_job_cluster,
        job_cluster_finished_task=end,
    )
