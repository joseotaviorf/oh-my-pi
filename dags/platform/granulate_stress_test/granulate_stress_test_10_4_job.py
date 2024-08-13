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
from bietlejuice.services.configuration_service import ConfigurationService
from os import path

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2021, 8, 24, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "15 * * * *"

CONTEXT = "granulate_stress_test"
DAG_NAME = f"{CONTEXT}_10_4_job"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
EXECUTION_HOURS_TIMEOUT = 2.0

config_service = ConfigurationService(CONTEXT)
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
spark_jobs_path = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/granulate_stress_test/"
)
artifacts_bucket = config_service.get_config("artifacts_bucket")

CLUSTER_DESCRIPTION = config_service.get_config("databricks_10_4_min_general_cluster")

if ENV == "prod":
    # Setting granulate configs
    CLUSTER_DESCRIPTION["init_scripts"].append(
        {
            "s3": {
                "destination": f"{artifacts_bucket}/granulate/sagent_installer_dbc-931ee6e0-6803.sh",
                "region": "",
            }
        }
    )
    CLUSTER_DESCRIPTION["custom_tags"].append(
        {"key": "granulate-cluster-name", "value": DAG_ID}
    )
    CLUSTER_DESCRIPTION["spark_env_vars"]["GRANULATE_JOB_NAME"] = DAG_ID


DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
DAG_OWNER = DAGOwnerEnum.DATA_INGESTION

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
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

authorize_ips_task = QuintoAndarDatabricksCheckJobTaskOperator(
    databricks_conn_id="databricks_job_cluster",
    dag=dag,
    task_id="authorize-ips",
    json={
        "spark_python_task": {
            "python_file": path.join(spark_jobs_path, f"authorize_ip.py"),
            "parameters": [],
        }
    },
    execution_timeout=timedelta(hours=EXECUTION_HOURS_TIMEOUT),
)

interact_with_metastore_task = QuintoAndarDatabricksCheckJobTaskOperator(
    databricks_conn_id="databricks_job_cluster",
    dag=dag,
    task_id="interact-with-metastore",
    json={
        "spark_python_task": {
            "python_file": path.join(spark_jobs_path, f"interact_with_metastore.py"),
            "parameters": [],
        }
    },
    execution_timeout=timedelta(hours=EXECUTION_HOURS_TIMEOUT),
)

execute_job_cluster_task >> authorize_ips_task >> interact_with_metastore_task
