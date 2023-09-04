import os
from datetime import datetime

from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from pendulum import timezone

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.services.configuration_service import ConfigurationService


ENV = os.environ.get("ENVIRONMENT")
SOURCE = "app_installed"
DAG_NAME = f"reverse_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
DAG_OWNER = DAGOwnerEnum.DATA_SS
MAIN_START_DATE = datetime(2022, 7, 12, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None

config_service = ConfigurationService(DAG_NAME)
datalake_bucket = config_service.get_config("datalake_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
reverse_spark_job_path = f"{s3_prefix}/spark_jobs/{DAG_NAME}/load_{DAG_NAME}.py"

cluster_description = config_service.get_config(
    "databricks_10_4_med_general_photon_cluster"
)
default_libraries = config_service.get_config("default_libraries")

minority_report_endpoint = config_service.get_config("minority_report_endpoint")
tables_to_send = config_service.get_config("tables_to_send")
dag_documentation = config_service.get_config("dag_documentation")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

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

load_tasks = []
for table in tables_to_send.keys():
    send_data_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load_{table}_data_to_minority_report",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": reverse_spark_job_path,
                "parameters": [
                    ENV,
                    datalake_bucket,
                    SOURCE,
                    minority_report_endpoint,
                    table,
                    tables_to_send[table]["type"],
                    tables_to_send[table]["key_name"],
                    "{{ ds }}",
                ],
            }
        },
    )
    load_tasks.append(send_data_task)

create_cluster_task >> load_tasks >> terminate_cluster_task
