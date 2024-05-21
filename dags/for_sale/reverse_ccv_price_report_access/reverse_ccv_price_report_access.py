from datetime import datetime
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from pendulum import timezone
import os

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

SOURCE = "ccv_price_report_access"
DAG_NAME = f"reverse_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
REVERSE_DESTINATION = "sns"

MAIN_START_DATE = datetime(2022, 7, 12, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))

config_service = ConfigurationService(DAG_NAME)

datalake_bucket = config_service.get_config("datalake_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

reverse_spark_job_path = (f"{s3_prefix}/spark_jobs/{DAG_NAME}/load_into_{REVERSE_DESTINATION}.py")

cluster_description = config_service.get_config("custom_cluster")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

default_libraries = config_service.get_config("default_libraries")
tables = config_service.get_config("tables")
database_name = config_service.get_config("database_name")
sns_topic_arn = config_service.get_config("sns_topic_arn")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_SALE,
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

load_to_sns_tasks = []
for table_name, table_config in tables.items():
    load_to_sns_tasks.append(
        QuintoAndarDatabricksSubmitRunOperator(
            task_id=f"load-{table_name}-into-{REVERSE_DESTINATION}".replace("_", "-"),
            dag=dag,
            json={
                "spark_python_task": {
                    "python_file": reverse_spark_job_path,
                    "parameters": [
                        database_name,
                        table_name,
                        table_config["event_type"],
                        sns_topic_arn,
                    ],
                }
            },
        )
    )

chain(create_cluster_task, load_to_sns_tasks)
chain(load_to_sns_tasks, terminate_cluster_task)
