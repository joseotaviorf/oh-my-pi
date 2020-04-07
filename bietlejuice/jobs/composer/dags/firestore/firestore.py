from datetime import datetime
import pendulum
from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG

# variable definitions
SOURCE = "firestore"
DAG_ID = "bietlejuice.{}".format(SOURCE)
ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 1, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "30 3 * * *"

# s3 paths setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = "{}/spark_jobs/{}/".format(S3_PREFIX, SOURCE)
LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

# cluster setup
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

# Job params
SOURCE_COLLECTIONS = {"offers": "lastSentDate"}


# Task builders
def create_collection_sub_dag(
    sub_dag_name, table, date_field, dag_id, schedule_interval, start_date
):
    collection_sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=dag_id,
        schedule_interval=schedule_interval,
        start_date=start_date,
    )._build_local_dag()

    load_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="load-{}-to-raw".format(table),
        dag=collection_sub_dag,
        json={
            "spark_python_task": {
                "python_file": "{}/load_firestore_into_datalake.py".format(
                    SPARK_JOBS_PATH
                ),
                "parameters": [
                    ENV,
                    DATALAKE_BUCKET,
                    SOURCE,
                    "{{ ds }}",
                    table,
                    date_field,
                ],
            }
        },
    )

    create_raw_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-{}-raw-external-table".format(table),
        dag=collection_sub_dag,
        json={
            "spark_python_task": {
                "python_file": "{}/create_external_table.py".format(SPARK_JOBS_PATH),
                "parameters": [
                    ENV,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                    SOURCE,
                    table,
                    "raw",
                ],
            }
        },
    )

    load_to_raw_task >> create_raw_external_table_task

    return collection_sub_dag


# Dag definition
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
)

# Create and Terminate Cluster Tasks
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

# Create Raw Tasks
for collection, date_field in SOURCE_COLLECTIONS.items():
    collection_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
        dag=dag,
        sub_dag_name="{}".format(collection),
        sub_dag_func=create_collection_sub_dag,
        table=collection,
        date_field=date_field,
        dag_id=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )
    create_cluster_task >> collection_sub_dag_task >> terminate_cluster_task
