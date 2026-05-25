import json
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List, Tuple

import yaml
from airflow import DAG
from airflow.decorators import task_group
from databricks_plugin import (
    QuintoAndarDatabricksCheckJobTaskOperator,
    QuintoAndarDatabricksExecuteJobClusterOperator,
)

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
        with open(path, "r", encoding="utf-8") as handle:
            loaded = yaml.safe_load(handle) or {}
        out.append((path.stem, loaded))
    return out


BASE_PARAMETERS = {
    "env": ENV,
    "dag_name": DAG_NAME,
    "bucket": bucket,
    "partition_date": "{{ data_interval_start | ds }}",
    "partition_hour": "{{ data_interval_start.strftime('%H') }}",
}


def create_execute_job_cluster_task(dag: DAG, task_id: str):
    return QuintoAndarDatabricksExecuteJobClusterOperator(
        databricks_conn_id=DATABRICKS_CONN_ID,
        dag=dag,
        task_id=task_id,
        cluster_configuration=get_cluster_config(CONFIG_SERVICE),
        access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
        libraries=get_libs(ENV),
    )


def create_load_table_task(dag: DAG, table_stem: str, table_spec: Dict[str, Any]):
    base_parameters = {
        **BASE_PARAMETERS,
        "target_schema": CORE_SCHEMA,
        "target_table": table_stem,
        "job_name": f"load_core_support_journey_{table_stem}",
        "table_config_json": json.dumps(table_spec),
    }
    base_parameters = parse_parameters(base_parameters)
    return QuintoAndarDatabricksCheckJobTaskOperator(
        databricks_conn_id=DATABRICKS_CONN_ID,
        dag=dag,
        task_id=f"load_core_support_journey_{table_stem}",
        json={
            "spark_python_task": {
                "python_file": f"{BASE_SPARK_JOB_PATH}core_model/support_journey/{table_stem}.py",
                "parameters": base_parameters,
            }
        },
        execution_timeout=timedelta(hours=1),
    )


@task_group(group_id="start_sensors")
def external_sensors():
    for external_dag_id, external_task_ids in EXTERNAL_SENSOR_SPECS.items():
        SStExternalTaskSensor(
            task_id=f"sensor_{external_dag_id.replace('.', '_')}",
            external_dag_id=external_dag_id,
            external_task_ids=external_task_ids,
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
    tags=["core_model", "support_journey", "SST"],
    max_active_runs=1,
    on_failure_callback=gchat_callback.dag_failure_alert,
) as dag:
    start = SStPlaceholderOperator(task_id="start")
    end = SStPlaceholderOperator(task_id="end")
    execute_job_cluster = create_execute_job_cluster_task(
        dag=dag, task_id="execute_core_support_journey_cluster"
    )

    external_sensors = external_sensors()

    load_tasks = []
    for stem, spec in list_table_specs_from_dir(TABLES_DIR):
        load_tasks.append(create_load_table_task(dag, stem, spec))

    start >> external_sensors >> execute_job_cluster >> load_tasks >> end
