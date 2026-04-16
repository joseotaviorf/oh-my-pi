from datetime import datetime, timedelta


from airflow import DAG
from typing import List, Dict

from bietlejuice.base.sst.airflow.operators.base import SStPlaceholderOperator
from bietlejuice.base.sst.airflow.common.common import (
    get_libs,
    get_cluster_config,
    parse_parameters,
)

from bietlejuice.base.sst.airflow.common.configs import DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST

from bietlejuice.base.databricks.cluster_permission_enum import ClusterPermissionEnum
from bietlejuice.base.databricks.databricks_group_name_enum import (
    DatabricksGroupNameEnum,
)
from bietlejuice.base.jiraops.jiraops_callback import JiraOpsCallback
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.notification.gchat_callback import GchatCallback
from bietlejuice.services.configuration_service import ConfigurationService
from databricks_plugin import (
    QuintoAndarDatabricksCheckJobTaskOperator,
    QuintoAndarDatabricksExecuteJobClusterOperator,
)
import os

#TODO: Move to only salesforce
DAG_NAME = "salesforce_cdc"
DAG_ID = f"bietlejuice.{DAG_NAME.replace('.', '_')}"
ENV = os.environ.get("ENVIRONMENT")
CONFIG_SERVICE = ConfigurationService(DAG_NAME)
DATABRICKS_CONN_ID = "databricks_new"
BIETLEJUICE_REPO_PATH = CONFIG_SERVICE.get_config("databricks_bietlejuice_repo_path")
BASE_SPARK_JOB_PATH = f"{BIETLEJUICE_REPO_PATH}/spark_jobs/{DAG_NAME}/"
BASE_SPARK_JOBS_PATH = f"{BIETLEJUICE_REPO_PATH}/spark_jobs/base/"
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
    task_id: str = None
):

    base_parameters = {
        **BASE_PARAMETERS,
        "target_schema": target_schema,
        "target_table": target_table,
        "job_name": f"load_{target_schema}_{target_table}",
        **parameters
    }
    #override task_id if provided
    task_id = f"load_{target_schema}_{target_table}" if not task_id else task_id
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

    start = SStPlaceholderOperator(
        task_id=f"start_{task_id}"
    )
    end = SStPlaceholderOperator(
        task_id=f"end_{task_id}"
    )
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
    #TODO: Uncomment callback when the dag is ready with all events and quality checks are implemented
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
    #TODO: Uncomment callback when the dag is ready with all events and quality checks are implemented
    # on_failure_callback=jiraops_callback.dag_failure_alert,
    max_active_runs=1,
 ) as dag:

    start, end = create_start_end_operator("salesforce")
    execute_job_cluster = create_execute_job_cluster_task(
            dag=dag,
            task_id="execute_cdc_cluster"
    )

    for event, parameters in EVENTS_CONFIG.items():
        event_table = f"events_{event.lower()}"
        threshold_time_hours = parameters.get("threshold_time_hours", 24)

        raw_task = create_sst_task(
            target_schema="datalake_salesforce_raw",
            target_table=event_table,
            entry_point="cdc_raw_ingestion",
            parameters=parameters,
        )
        clean_task = create_sst_task(
            target_schema="datalake_salesforce_clean",
            target_table=event_table,
            entry_point="cdc_clean",
            parameters={
                "source_schema": "datalake_salesforce_raw",
                "sync_hive": "True",
            },
        )

        if parameters.get("skip_quality_contracts", False):
            execute_job_cluster >> raw_task >> clean_task >> end
        else:
            quality_contract_raw = create_sst_task(
                target_schema="datalake_salesforce_raw",
                target_table=event_table,
                entry_point="generic_quality_checks",
                parameters={
                    "threshold_time_hours": threshold_time_hours,
                },
                task_id=f"quality_contract_checks_raw_{event_table}",
            )
            quality_contract_clean = create_sst_task(
                target_schema="datalake_salesforce_clean",
                target_table=event_table,
                entry_point="generic_quality_checks",
                parameters={
                    "threshold_time_hours": threshold_time_hours,
                },
                task_id=f"quality_contract_checks_clean_{event_table}",
            )
            execute_job_cluster >> raw_task >> quality_contract_raw >> clean_task >> quality_contract_clean >> end

    start >> execute_job_cluster
