from datetime import datetime
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from pendulum import timezone
import os
import json

from airflow.models import DAG
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

ENV = os.environ.get("ENVIRONMENT")

SOURCE = "robbyson"
DAG_NAME = f"reverse_{SOURCE}_access"
DAG_ID = f"bietlejuice.{DAG_NAME}"

MAIN_START_DATE = datetime(2024, 3, 26, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))

config_service = ConfigurationService(DAG_NAME)

s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
reverse_spark_job_path = f"{s3_prefix}/spark_jobs/{DAG_NAME}/load_into_robbyson_api.py"

cluster_description = config_service.get_config("databricks_10_4_med_general_cluster")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
default_libraries = config_service.get_config("default_libraries")

doc_md_chart_url = config_service.get_config("doc_md_chart_url")
dag_documentation = config_service.get_config("dag_documentation")
api_url = config_service.get_config("api_url")
endpoint = config_service.get_config("endpoint")
configurations = config_service.get_config("configurations")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_SS,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=SOURCE,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=dag_documentation,
        dag_owner=DAGOwnerEnum.DATA_SS,
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

external_api_load_task= []

for key, value in configurations.items():
    external_api_load_task.append(
        QuintoAndarDatabricksSubmitRunOperator(
            task_id=f"load-{key}-analysts-data-into-robbyson-api",
            dag=dag,
            json={
                "spark_python_task": {
                    "python_file": reverse_spark_job_path,
                    "parameters": [
                        ENV,
                        SOURCE,
                        key,
                        api_url,
                        endpoint,
                        "{{ ds }}",
                        json.dumps(value)
                    ],
                }
            },
        )
    )

chain(create_cluster_task, external_api_load_task)
chain(external_api_load_task, terminate_cluster_task)
