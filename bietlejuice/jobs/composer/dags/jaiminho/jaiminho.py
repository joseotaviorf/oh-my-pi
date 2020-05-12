from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG

# ENV params setup
ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")

# DAG params setup
SOURCE = "jaiminho"
DAG_ID = f"bietlejuice.{SOURCE}"
sp_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 5, 5, 0, 0, 0, tzinfo=sp_tz)
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"

# S3 paths setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
S3_BUCKET = Variable.get("databricks_s3_bucket")
DATA_LAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"

# cluster setup
LOGS_OUTPUT_PATH = f"s3://{S3_BUCKET}/logs/jobs/{SOURCE}"
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_jaiminho", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

# DAG definition
main_dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
)

# Tasks definition
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=main_dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=main_dag, task_id="terminate-cluster"
)

# Create Raw tasks
load_raw_table = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load-tables-to-data-lake-raw",
    dag=main_dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH
            + "load_incremental_tables_into_data_lake_raw.py",
            "parameters": [ENV, SOURCE, DATA_LAKE_BUCKET, "{{ ds }}"],
        }
    },
)

create_cluster_task >> load_raw_table >> terminate_cluster_task
