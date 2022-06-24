from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.services import ConfigurationService

DAG_NAME = "services_integration_validations"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(
    2021, 1, 20, 0, 0, 0, tzinfo=pendulum.timezone("America/Sao_Paulo")
)
MAIN_SCHEDULE_INTERVAL = "0 13,16,18,20 * * *"

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_9_1_min_general_cluster", deserialize_json=True
)

config_service = ConfigurationService()
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/{DAG_NAME}"

artifacts_s3_bucket = config_service.get_config("artifacts_bucket")
custom_libraries = [
    {
        "jar": f"{artifacts_s3_bucket}/mysql-connector-java/mysql-connector-java-5.1.47.jar"
    },
    {"pypi": {"package": "hubspot-api-client==5.0.0"}},
    {
        "whl": f"{artifacts_s3_bucket}/pipedrive-api-client-python/"
        f"quintoandar_pipedrive_api_client-0.1.0-py2.py3-none-any.whl"
    },
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_AVAILABILITY,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=custom_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

run_validations_suites = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"run-validations-suites",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": f"{base_spark_jobs_path}/run_validation_suites.py"
        }
    },
)

create_cluster_task >> run_validations_suites >> terminate_cluster_task
