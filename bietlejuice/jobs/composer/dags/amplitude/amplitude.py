from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG

DAG_ID = "bietlejuice.amplitude"
ENV = Variable.get("environment")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

LOAD_EVENTS_INTO_DATALAKE_RAW_FILE_PATH = "{}/spark_jobs/amplitude/load_events_into_datalake_raw.py".format(
    S3_PREFIX
)
EVENTS_RAW_TO_CLEAN_FILE_PATH = "{}/spark_jobs/amplitude/events_raw_to_clean.py".format(
    S3_PREFIX
)
CREATE_CLEAN_EXTERNAL_TABLES_FILE_PATH = "{}/spark_jobs/amplitude/create_clean_external_tables.py".format(
    S3_PREFIX
)

ADD_CLEAN_EVENTS_PARTITIONS = "{}/spark_jobs/amplitude/add_clean_events_partitions.py".format(
    S3_PREFIX
)

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_memory_optimized_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)


dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime(2019, 1, 1, 0, 0, 0),
    schedule_interval="30 5 * * *",
    max_active_runs=1,
    catchup=False,
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

events_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="events-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_EVENTS_INTO_DATALAKE_RAW_FILE_PATH,
            "parameters": ["{{ ds }}", ENV],
        }
    },
)

events_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="events-raw-to-clean",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": EVENTS_RAW_TO_CLEAN_FILE_PATH,
            "parameters": ["{{ ds }}", ENV],
        }
    },
)

create_clean_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-clean-external-tables",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": CREATE_CLEAN_EXTERNAL_TABLES_FILE_PATH,
            "parameters": [ENV],
        }
    },
)

add_amplitude_events_partitions = QuintoAndarDatabricksSubmitRunOperator(
    task_id="add-amplitude-events-partitions",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": ADD_CLEAN_EVENTS_PARTITIONS,
            "parameters": ["{{ ds }}", ENV],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

airflow_helpers.chain(
    create_cluster_task,
    events_to_datalake_raw_task,
    events_raw_to_clean_task,
    [add_amplitude_events_partitions, create_clean_external_tables_task],
    terminate_cluster_task,
)
