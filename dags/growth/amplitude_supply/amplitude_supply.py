import os
from datetime import datetime, timedelta

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from airflow.operators.dummy_operator import DummyOperator
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from pendulum import timezone

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.configuration_service import ConfigurationService

# Pipeline inputs
SOURCE = "amplitude_supply"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2019, 1, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None
CLUSTER_DESCRIPTION = "custom_cluster"

EXECUTION_TIMEOUT_HOURS = 3

config_service = ConfigurationService(SOURCE)
PARTITION_COLS = config_service.get_config("partition_cols_dag")
INCREMENTAL_PARTITIONS = config_service.get_config("incremental_partitions")
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
source_path = SOURCE.split('_')[0]

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

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

events_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="events-supply-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "load_amplitude_supply_raw.py",
            "parameters": [ENV, datalake_bucket, source_path, "{{ ds }}"],
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