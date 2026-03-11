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

from bietlejuice.services.configuration_service import ConfigurationService
from databricks_plugin import ( 
    QuintoAndarDatabricksCheckJobTaskOperator,
    QuintoAndarDatabricksExecuteJobClusterOperator,
)
import os 

#TODO: Move to only salesforce 
DAG_NAME = "salesforce_cdc"
DAG_ID = f"sst.{DAG_NAME.replace('.', '_')}"
ENV = os.environ.get("ENVIRONMENT")
CONFIG_SERVICE = ConfigurationService(DAG_NAME)
DATABRICKS_CONN_ID = "databricks_new" 
BIETLEJUICE_REPO_PATH  = CONFIG_SERVICE.get_config("databricks_bietlejuice_repo_path")
BASE_SPARK_JOB_PATH = f"{BIETLEJUICE_REPO_PATH}/spark_jobs/{DAG_NAME}/"

# Use config and DAG constants so the DAG works without requiring Airflow Variables
# (bucket/dag_name/environment). Config is loaded per environment (forno_conf vs prod_conf).
try:
    bucket = CONFIG_SERVICE.get_config("datalake_bucket")
except (IndexError, KeyError):
    bucket = "5a-datalake-forno"


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



EVENTS_CONFIG = {
    "account": {
        "event_path": "raw/salesforce/AccountEvent",
    },
    "case": {
        "event_path": "raw/salesforce/CaseEvent",
    },
    "checklist": {
        "event_path": "raw/salesforce/Checklist__Event",
    },
    "contract": {
        "event_path": "raw/salesforce/ContractEvent",
    },
    "contract_member": {
        "event_path": "raw/salesforce/ContractMember__Event",
    },
    "email_message": {
        "event_path": "raw/salesforce/EmailMessageEvent",
    },
    "relisting_context": {
        "event_path": "raw/salesforce/RelistingContext__Event",
    },
    "user": {
        "event_path": "raw/salesforce/UserEvent",
    }
}


jiraops_callback = JiraOpsCallback()
default_args = {
    "owner": "Data SS",
    "depends_on_past": True,   # safer unless you truly need strict chaining
    "email_on_retry": False,
    "retries": 1,
    "on_failure_callback": jiraops_callback.task_failure_alert,
}
with DAG(
    dag_id=DAG_ID,
    default_args=default_args,
    schedule_interval="0 * * * *",  
    start_date=datetime(2026, 3, 12),
    catchup=False,
    tags=["SST", "SF", "salesforce"],  # better formatting
    on_failure_callback=jiraops_callback.dag_failure_alert,
    max_active_runs=1,
 ) as dag:

    start, end = create_start_end_operator("salesforce") 
    execute_job_cluster = create_execute_job_cluster_task(
            dag=dag,
            task_id="execute_cdc_cluster"
    )

    for event, parameters in EVENTS_CONFIG.items():
        execute_job_cluster >> create_sst_task(
            target_schema="datalake_salesforce_raw",
            target_table=f"events_{event.lower()}",
            entry_point="cdc_raw_ingestion",
            parameters=parameters,
        )>> create_sst_task(
            target_schema="datalake_salesforce_clean",
            target_table=f"events_{event.lower()}",
            entry_point="cdc_clean",
            parameters={
                "source_schema": "datalake_salesforce_raw",
            },
        ) >> end 
        
        
   
    start >>  execute_job_cluster
