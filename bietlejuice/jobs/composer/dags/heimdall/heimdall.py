from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG

DAG_ID = "heimdall"
ENV = Variable.get("environment")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

LOAD_HEIMDALL_INTO_DATALAKE_RAW_FILE_PATH = (
    S3_PREFIX + "/spark_jobs/{}/load_heimdall_into_datalake.py".format(DAG_ID)
)
CREATE_RAW_EXTERNAL_TABLES_FILE_PATH = (
    S3_PREFIX + "/spark_jobs/{}/create_raw_external_tables.py".format(DAG_ID)
)
CREATE_CLEAN_TABLE_FILE_PATH = (
    S3_PREFIX + "/spark_jobs/{}/create_clean_table_in_datalake.py".format(DAG_ID)
)

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {
        "maven": {
            "coordinates": "org.mongodb.spark:mongo-spark-connector_2.11:2.4.0",
            "repo": "https://mvnrepository.com/artifact/org.mongodb.spark/mongo-spark-connector",
        }
    }
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "30 4 * * *"

dag = DAG(
    dag_id="bietlejuice.{}".format(DAG_ID),
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=False,
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

heimdall_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="heimdall-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_HEIMDALL_INTO_DATALAKE_RAW_FILE_PATH,
            "parameters": [ENV],
        }
    },
)

create_raw_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-raw-external-tables",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": CREATE_RAW_EXTERNAL_TABLES_FILE_PATH,
            "parameters": [ENV],
        }
    },
)

create_clean_table_in_datalake = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create_clean_table_in_datalake",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": CREATE_CLEAN_TABLE_FILE_PATH,
            "parameters": ["heimdall", ENV, DAG_ID],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> heimdall_to_datalake_raw_task >> [
    create_raw_external_tables_task,
    create_clean_table_in_datalake,
] >> terminate_cluster_task
