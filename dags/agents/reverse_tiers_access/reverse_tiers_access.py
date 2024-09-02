import os
import json
from datetime import datetime

from airflow.models import DAG
from airflow.utils.helpers import chain
from airflow.operators.python_operator import ShortCircuitOperator
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from pendulum import timezone

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_builders.main_builder.short_circuit_functions.dag_run_date_validators import (
    DAGRunDateValidators,
)
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.services.configuration_service import ConfigurationService


ENV = os.environ.get("ENVIRONMENT")
SOURCE = "tiers"
DAG_NAME = f"reverse_{SOURCE}_access"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2024, 8, 23, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None
DAG_OWNER = DAGOwnerEnum.DATA_AGENTS

config_service = ConfigurationService(DAG_NAME)
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
datalake_s3_bucket = config_service.get_config("datalake_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
reverse_spark_job_path = f"{s3_prefix}/spark_jobs/{DAG_NAME}/load_reverse_{SOURCE}.py"

cluster_description = config_service.get_config(
    "databricks_12_2_med_general_photon_cluster"
)
default_libraries = config_service.get_config("default_libraries")
external_s3_bucket = config_service.get_config("external_s3_bucket")
dag_documentation = config_service.get_config("dag_documentation")

tables_to_send = config_service.get_config("tables_to_send")
range_of_days_to_run = config_service.get_config("range_of_days_to_run")
webhook_key = config_service.get_config("notification_webhooks_keys")["data_quality"]

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

skip_run_task = ShortCircuitOperator(
    task_id=f"check-day-to-skip-execution",
    python_callable=DAGRunDateValidators.check_is_in_range_of_days,
    op_args=["{{ macros.ds_add(ds, 1) }}", range_of_days_to_run],
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

load_tasks = []
for table in tables_to_send.keys():
    send_data_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load_{table}_data_into_external_bucket",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": reverse_spark_job_path,
                "parameters": [
                    ENV,
                    SOURCE,
                    datalake_s3_bucket,
                    external_s3_bucket,
                    table,
                    webhook_key,
                    "{{ ds }}",
                ],
            }
        },
    )
    load_tasks.append(send_data_task)

chain(*load_tasks)
chain(skip_run_task, create_cluster_task, load_tasks)
chain(load_tasks, terminate_cluster_task)
