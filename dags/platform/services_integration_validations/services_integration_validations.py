from datetime import datetime

import pendulum
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.services import ConfigurationService

DAG_NAME = "services_integration_validations"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(
    2021, 1, 20, 0, 0, 0, tzinfo=pendulum.timezone("America/Sao_Paulo")
)
MAIN_SCHEDULE_INTERVAL = "0 13,16,18,20 * * *"


config_service = ConfigurationService()
CLUSTER_DESCRIPTION = config_service.get_config("databricks_10_4_med_general_cluster")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/{DAG_NAME}"

artifacts_bucket = config_service.get_config("artifacts_bucket")
default_libraries = config_service.get_config("default_libraries")
custom_libraries = [
    {"maven": {"coordinates": "mysql:mysql-connector-java:5.1.47"}},
    {"pypi": {"package": "hubspot-api-client==5.0.0"}},
    {"pypi": {"package": "google-auth==2.13.0"}},
    {"pypi": {"package": "google-api-python-client==2.55.0"}},
    {"pypi": {"package": "validations-engine==2.0.0"}},
    {
        "whl": f"{artifacts_bucket}/facebook-api-client-python/"
        f"quintoandar_facebook_api_client-0.1.2-py2.py3-none-any.whl"
    },
    {
        "whl": f"{artifacts_bucket}/gsheets-api-client-python/"
        f"quintoandar_gsheets_api_client-0.7.0-py2.py3-none-any.whl"
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
    libraries=default_libraries + custom_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

run_validations_suites = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"run-validations-suites",
    dag=dag,
    retries=0,
    json={
        "spark_python_task": {
            "python_file": f"{base_spark_jobs_path}/run_validation_suites.py"
        }
    },
)

create_cluster_task >> run_validations_suites >> terminate_cluster_task
