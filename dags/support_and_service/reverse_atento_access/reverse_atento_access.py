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

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG and Jobs params setup
SOURCE = "atento"
DAG_NAME = f"reverse_{SOURCE}_access"
DAG_ID = f"bietlejuice.{DAG_NAME}"

MAIN_START_DATE = datetime(2023, 10, 11, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None
DAG_OWNER = DAGOwnerEnum.DATA_SS

config_service = ConfigurationService(DAG_NAME)

# S3 path setup
datalake_bucket = config_service.get_config("datalake_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

reverse_spark_job_path = (
    f"{s3_prefix}/spark_jobs/{DAG_NAME}/load_s3_data_into_external_bucket.py"
)

cluster_description = config_service.get_config("custom_cluster")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

default_libraries = config_service.get_config("default_libraries")
external_s3_bucket = config_service.get_config("external_s3_bucket")
dag_documentation = config_service.get_config("dag_documentation")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=DAG_NAME,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=dag_documentation,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        dag_owner=DAG_OWNER,
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

external_bucket_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"load_s3_data_into_external_bucket",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": reverse_spark_job_path,
            "parameters": [
                ENV, 
                datalake_bucket, 
                SOURCE, 
                external_s3_bucket
            ],
        }
    },
)

chain(create_cluster_task, external_bucket_task)
chain(external_bucket_task, terminate_cluster_task)
