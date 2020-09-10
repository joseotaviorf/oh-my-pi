from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG


# ENV setup
ENV = Variable.get("environment")

# DAG params setup
SOURCE = "firestore"
DAG_ID = f"{SOURCE}_audit"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 8, 29, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "30 3 * * *"

# s3 paths setup
DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{DAG_ID}"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{DAG_ID}/"

# cluster setup
CLUSTER_DESCRIPTION = Variable.get(
    f"databricks_bietlejuice_{DAG_ID}_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)
PUBSUB_CREDENTIALS_PATH = Variable.get("pubsub_credentials_path")
CLUSTER_DESCRIPTION["spark_env_vars"][
    "GOOGLE_APPLICATION_CREDENTIALS"
] = PUBSUB_CREDENTIALS_PATH

# job params
PROJECT_ID = Variable.get("pwa_google_project_id")
SUBSCRIPTIONS = [
    {
        "subscription_id": "domainSaleOffer-audit-data-engineering-subscription",
        "table_name": "sale_offer",
    }
]


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
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

# Creating sub dags
for subscription in SUBSCRIPTIONS:

    # TODO: Migrate this logic to a separate function when we have the Clean Spark Job (use Jira DAG as template)

    load_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{subscription['table_name']}-into-raw",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "load_firestore_audit_into_raw.py",
                "parameters": [
                    ENV,
                    SOURCE,
                    DATALAKE_BUCKET,
                    PROJECT_ID,
                    PUBSUB_CREDENTIALS_PATH,
                    subscription["subscription_id"],
                    subscription["table_name"],
                ],
            }
        },
    )
    create_cluster_task >> load_to_raw_task >> terminate_cluster_task
