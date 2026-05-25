import os
from datetime import datetime, timedelta
from typing import Dict, Optional

from airflow import DAG
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
from bietlejuice.services.configuration_service import ConfigurationService

DAG_NAME = "salesforce_marketing_cloud"
DAG_ID = f"bietlejuice.{DAG_NAME.replace('.', '_')}"
ENV = os.environ.get("ENVIRONMENT")
CONFIG_SERVICE = ConfigurationService(DAG_NAME)
DATABRICKS_CONN_ID = "databricks_new"
BIETLEJUICE_REPO_PATH = CONFIG_SERVICE.get_config("databricks_bietlejuice_repo_path")
BASE_SPARK_JOB_PATH = f"{BIETLEJUICE_REPO_PATH}/spark_jobs/{DAG_NAME}/"
BASE_SPARK_JOBS_PATH = f"{BIETLEJUICE_REPO_PATH}/spark_jobs/base/"
RELATIVE_DAG_PATH = "dags/support_and_service/salesforce_marketing_cloud"


def create_task(
    target_schema: str,
    target_table: str,
    entry_point: str,
    parameters: Optional[Dict[str, str]] = None,
):
    base_parameters = {
        "env": ENV,
        "dag_name": DAG_NAME,
        "bucket": CONFIG_SERVICE.get_config("datalake_bucket"),
        "partition_date": "{{ data_interval_start | ds }}",
        "target_schema": target_schema,
        "target_table": target_table,
        "job_name": f"load_{target_schema}_{target_table}",
        **(parameters or {}),
    }
    task_id = f"load_{target_schema}_{target_table}"
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


def create_start_end_operator(task_id: str):
    start = SStPlaceholderOperator(task_id=f"start_{task_id}")
    end = SStPlaceholderOperator(task_id=f"end_{task_id}")
    return start, end


OBJECTS_CONFIG = CONFIG_SERVICE.get_config("objects_config")
RAW_SCHEMA = CONFIG_SERVICE.get_config("raw_schema")
CLEAN_SCHEMA = CONFIG_SERVICE.get_config("clean_schema")


gchat_callback = GchatCallback()
default_args = {
    "owner": "Data SS",
    "email_on_retry": False,
    "retries": 1,
    "on_failure_callback": gchat_callback.task_failure_alert,
}
with DAG(
    dag_id=DAG_ID,
    default_args=default_args,
    schedule_interval="0 0 * * *",
    start_date=datetime(2026, 3, 12),
    catchup=False,
    tags=["SST", "SFMC", "salesforce"],
    on_failure_callback=gchat_callback.dag_failure_alert,
    max_active_runs=1,
) as dag:
    start, end = create_start_end_operator("salesforce")
    execute_job_cluster = create_execute_job_cluster_task(
        dag=dag,
        task_id="execute_sfmc_cluster",
    )

    for table_name, object_config in OBJECTS_CONFIG.items():
        (
            execute_job_cluster
            >> create_task(
                target_schema=RAW_SCHEMA,
                target_table=table_name,
                entry_point="raw",
                parameters={"external_key": object_config["external_identifier"]},
            )
            >> create_task(
                target_schema=CLEAN_SCHEMA,
                target_table=table_name,
                entry_point="clean",
                parameters={
                    "source_schema": RAW_SCHEMA,
                    "sync_hive": "True",
                },
            )
            >> end
        )

    start >> execute_job_cluster
