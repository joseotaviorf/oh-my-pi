from datetime import datetime
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from pendulum import timezone
import os
import json

from airflow.models import DAG
from airflow.utils.helpers import chain
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

ENV = os.environ.get("ENVIRONMENT")

SOURCE = "webhelp"
DAG_NAME = f"reverse_{SOURCE}_access"
DAG_ID = f"bietlejuice.{DAG_NAME}"

MAIN_START_DATE = datetime(2023, 8, 23, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))

config_service = ConfigurationService(DAG_NAME)

datalake_bucket = config_service.get_config("datalake_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

reverse_spark_job_path = f"{s3_prefix}/spark_jobs/{DAG_NAME}/load_into_azure_blob_storage.py"

cluster_description = config_service.get_config("custom_cluster")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

default_libraries = config_service.get_config("default_libraries")
database_name = config_service.get_config("database_name")
tables = config_service.get_config("tables")
azure_container_name = config_service.get_config("azure_container_name")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_SS,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID, ENV=ENV
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

external_bucket_task= []
for table_name, table_config in tables.items():
    external_bucket_task.append(
        QuintoAndarDatabricksSubmitRunOperator(
            task_id=f"load-{table_name}-table-into-azure-blob-storage",
            dag=dag,
            json={
                "spark_python_task": {
                    "python_file": reverse_spark_job_path,
                    "parameters": [
                        ENV, 
                        SOURCE, 
                        database_name, 
                        table_name, 
                        azure_container_name,
                        table_config['context'],
                        "{{ ds }}"
                    ],
                }
            },
        )
    )

chain(create_cluster_task, external_bucket_task)
chain(external_bucket_task, terminate_cluster_task)
