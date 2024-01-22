import os
import json
from datetime import datetime

from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksExecuteJobClusterOperator,
)
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.task_creator_factory import (
    TaskCreatorFactory,
    TaskEnum,
)
from pendulum import timezone

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.services.configuration_service import ConfigurationService


ENV = os.environ.get("ENVIRONMENT")
SOURCE = "bpo_performance"
DAG_NAME = f"reverse_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2024, 1, 18, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None
DAG_OWNER = DAGOwnerEnum.DATA_SS

config_service = ConfigurationService(DAG_NAME)
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
reverse_spark_job_path = f"{s3_prefix}/spark_jobs/{DAG_NAME}/load_{DAG_NAME}.py"

cluster_description = config_service.get_config(
    "databricks_10_4_min_general_photon_cluster"
)
default_libraries = config_service.get_config("default_libraries")
dag_documentation = config_service.get_config("dag_documentation")

tables_to_send = config_service.get_config("tables_to_send")
minority_report_endpoint = config_service.get_config("minority_report_endpoint")

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

execute_job_cluster_task = QuintoAndarDatabricksExecuteJobClusterOperator(
    databricks_conn_id="databricks_job_cluster",
    dag=dag,
    task_id="execute-job-cluster",
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries,
)

dag_execution_context = DagExecutionContext(
    dag=dag, 
    environment=ENV, 
    bucket="", 
    base_spark_jobs_path=reverse_spark_job_path, 
    dag_args={}, 
    workflow_args={}, 
    cluster_args={}
)
task_creator_factory = TaskCreatorFactory(dag_execution_context)
dummy_job_cluster_finished_task_creator = task_creator_factory.get_task_creator(
    TaskEnum.DUMMY_JOB_CLUSTER_FINISHED
).create_task()

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
                    DAG_NAME,
                    minority_report_endpoint,
                    table,
                    json.dumps(tables_to_send[table]),
                    "{{ ds }}",
                ],
            }
        },
    )
    load_tasks.append(send_data_task)

execute_job_cluster_task >> load_tasks >> dummy_job_cluster_finished_task_creator
