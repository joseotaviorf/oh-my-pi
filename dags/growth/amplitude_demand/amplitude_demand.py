import os
from datetime import datetime, timedelta

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from pendulum import timezone

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.services.configuration_service import ConfigurationService

# Pipeline inputs
SOURCE = "amplitude_demand"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2019, 1, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "00 23 * * *"
CLUSTER_DESCRIPTION = "custom_cluster"

EXECUTION_TIMEOUT_HOURS = 2

config_service = ConfigurationService(SOURCE)
EXTRA_SPARK_CONF = config_service.get_config("spark_conf")

datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
raw_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
artifacts_bucket = config_service.get_config("artifacts_bucket")
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
cluster_configuration["spark_conf"].update(EXTRA_SPARK_CONF)
del cluster_configuration["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"]
del cluster_configuration["data_security_mode"]
del cluster_configuration["single_user_name"]

default_libraries = config_service.get_config("default_libraries")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
ENV = os.environ.get("ENVIRONMENT")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(databricks_conn_id="databricks_old", dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(databricks_conn_id="databricks_old", dag=dag, task_id="terminate-cluster"
)

events_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_old", task_id="events-demand-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "load_amplitude_demand_raw.py",
            "parameters": [ENV, datalake_bucket, SOURCE, "{{ ds }}"],
        }
    },
    execution_timeout=timedelta(hours=EXECUTION_TIMEOUT_HOURS),
)

# raw tasks dependencies
airflow_helpers.chain(
    create_cluster_task,
    events_to_datalake_raw_task,
    terminate_cluster_task,
)