import os
import json
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from airflow.utils.helpers import chain
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.opsgenie.opsgenie_callback import OpsgenieCallback


ENV = os.environ.get("ENVIRONMENT")
SOURCE = "minority_report_ss"
DAG_NAME = f"reverse_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
DAG_OWNER = DAGOwnerEnum.DATA_SS
MAIN_START_DATE = datetime(2023, 11, 28, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None

config_service = ConfigurationService(DAG_NAME)
datalake_bucket = config_service.get_config("datalake_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
reverse_spark_job_path = f"{s3_prefix}/spark_jobs/{DAG_NAME}/load_{DAG_NAME}.py"

cluster_description = config_service.get_config("custom_cluster")

cluster_description["data_security_mode"] = "SINGLE_USER"
cluster_description["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
cluster_description["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = "quintoandar_{{ var.value.environment }}"
default_libraries = config_service.get_config("default_libraries")
custom_libraries = [
    {"pypi": {"package": "kafka-python==2.0.3"}},
]

kafka_servers = config_service.get_config("kafka_servers")
kafka_topic = config_service.get_config("kafka_topic")
tables = config_service.get_config("tables")
dag_documentation = config_service.get_config("dag_documentation")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
opsgenie_callback = OpsgenieCallback()
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
        "on_failure_callback": opsgenie_callback.task_failure_alert,
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

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries + custom_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(databricks_conn_id="databricks_new", dag=dag, task_id="terminate-cluster"
)

load_tasks = []
for table in tables.keys():
    send_data_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=f"load_{table}_data",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": reverse_spark_job_path,
                "parameters": [
                    DAG_NAME,
                    kafka_servers,
                    kafka_topic,
                    tables[table]["type"],
                    tables[table]["key_name"],
                    tables[table]["key_value"],
                    table,
                    "{{ ds }}",
                ],
            }
        },
    )
    load_tasks.append(send_data_task)

chain(create_cluster_task, load_tasks)
chain(load_tasks, terminate_cluster_task)
