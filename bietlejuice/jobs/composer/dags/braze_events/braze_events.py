from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG


ENV = Variable.get("environment")

SOURCE = "braze"
DAG_ID = f"{SOURCE}_events"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 11, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "30 0 * * *"

ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
BRAZE_BUCKET = Variable.get("braze_bucket")

LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{DAG_ID}"
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{DAG_ID}"

CLUSTER_DESCRIPTION = Variable.get(
    f"databricks_bietlejuice_{DAG_ID}_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# Names of app groups must match the directories created in Braze's S3 bucket
APP_GROUPS = ["owners", "tenants"]


dag = DAG(
    dag_id=f"bietlejuice.{DAG_ID}",
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

# Creating sub dags
for app_group in APP_GROUPS:

    load_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{app_group}-into-raw",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/load_braze_events_into_datalake.py",
                "parameters": [
                    ENV,
                    SOURCE,
                    DATALAKE_BUCKET,
                    BRAZE_BUCKET,
                    app_group,
                    "{{ ds }}",
                ],
            }
        },
    )

    create_cluster_task >> load_to_raw_task >> terminate_cluster_task
