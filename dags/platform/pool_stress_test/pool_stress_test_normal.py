import os
from datetime import datetime, timedelta

import pendulum
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCheckJobTaskOperator,
    QuintoAndarDatabricksExecuteJobClusterOperator,
)
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks.cluster_permission_enum import ClusterPermissionEnum
from bietlejuice.base.databricks.databricks_group_name_enum import (
    DatabricksGroupNameEnum,
)
from bietlejuice.base.opsgenie.opsgenie_callback import OpsgenieCallback

from bietlejuice.services.configuration_service import ConfigurationService
from os import path

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2021, 8, 24, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 * * * *"

CONTEXT = "pool_stress_test"
DAG_NAME = f"{CONTEXT}_normal"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
EXECUTION_HOURS_TIMEOUT = 2.0

config_service = ConfigurationService(CONTEXT)
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
spark_jobs_path = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/pool_stress_test/"
)
artifacts_bucket = config_service.get_config("artifacts_bucket")

# Picking this one because it's m5a.xlarge, and is already configured with a cluster pool
CLUSTER_DESCRIPTION = config_service.get_config("databricks_10_4_med_general_cluster")
CLUSTER_DESCRIPTION["num_workers"] = 1


DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
DAG_OWNER = DAGOwnerEnum.DATA_INGESTION
opsgenie_callback = OpsgenieCallback()
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
        "on_failure_callback": opsgenie_callback.task_failure_alert,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=None,
)

execute_job_cluster_task = QuintoAndarDatabricksExecuteJobClusterOperator(
    databricks_conn_id="databricks_job_cluster",
    dag=dag,
    task_id="execute-job-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

wait_half_hour_task = QuintoAndarDatabricksCheckJobTaskOperator(
    databricks_conn_id="databricks_job_cluster",
    dag=dag,
    task_id="wait-half-hour",
    json={
        "spark_python_task": {
            "python_file": path.join(spark_jobs_path, f"wait_half_hour.py"),
            "parameters": [],
        }
    },
    execution_timeout=timedelta(hours=EXECUTION_HOURS_TIMEOUT),
)

execute_job_cluster_task >> wait_half_hour_task
