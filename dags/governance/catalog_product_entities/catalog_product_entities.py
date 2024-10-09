from datetime import datetime, timedelta
from pendulum import timezone
import os

from airflow.models import DAG
from airflow.utils.helpers import chain
from databricks_plugin import (
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.base_task_group import BaseTaskGroup
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum


ENV = os.environ.get("ENVIRONMENT")
CONTEXT = "catalog_product_entities"
DAG_ID = f"bietlejuice.{CONTEXT}"
MAIN_START_DATE = datetime(2021, 10, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 13 * * wed"

config_service = ConfigurationService(CONTEXT)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)

SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{CONTEXT}/"

CLUSTER_DESCRIPTION = config_service.get_config(
    "databricks_12_2_min_general_photon_cluster"
)
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.DATA_PLATFORM_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
DEFAULT_LIBRARIES = config_service.get_config("default_libraries")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GOVERNANCE,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(CONTEXT).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=DEFAULT_LIBRARIES,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

propagate_bigid_entities_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=CONTEXT,
    json={
        "spark_python_task": {
            "python_file": f"{SPARK_JOB_PATH}/send_bigid_entities_to_metadata_propagator.py",
            "parameters": [ENV, "{{ ds }}"],
        }
    },
    execution_timeout=timedelta(hours=BaseTaskGroup.DEFAULT_EXECUTION_TIMEOUT_HOURS),
)

chain(create_cluster_task, propagate_bigid_entities_task, terminate_cluster_task)
