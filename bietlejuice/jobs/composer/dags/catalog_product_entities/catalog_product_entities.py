from datetime import datetime, timedelta
from pendulum import timezone
import os

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseTaskGroup, DAGOwnerEnum
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)


ENV = os.environ.get("ENVIRONMENT")
CONTEXT = "catalog_product_entities"
DAG_ID = f"bietlejuice.{CONTEXT}"
MAIN_START_DATE = datetime(2021, 10, 1, tzinfo=timezone("America/Sao_Paulo"))

config_service = ConfigurationService(CONTEXT)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)

SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{CONTEXT}/"

CLUSTER_DESCRIPTION = Variable.get(
    f"databricks_minimum_resources_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["spark_env_vars"]["ENVIRONMENT"] = ENV
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{spark_jobs_logs_path}{DAG_ID}"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GOVERNANCE,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(CONTEXT).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
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
