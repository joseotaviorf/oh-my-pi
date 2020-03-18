from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG

SOURCE = "autodialer"
ENV = Variable.get("environment")

# S3 paths setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
S3_BUCKET = Variable.get("databricks_s3_bucket")
DATA_LAKE_BUCKET = Variable.get("datalake_bucket")

SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"

# cluster setup
LOGS_OUTPUT_PATH = f"s3://{S3_BUCKET}/logs/jobs/{SOURCE}"
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_memory_optimized_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

# DAG definition
sp_tz = pendulum.timezone("America/Sao_Paulo")
main_dag = DAG(
    dag_id=f"bietlejuice.{SOURCE}",
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime(2020, 3, 16, 0, 0, 0, tzinfo=sp_tz),
    schedule_interval="0 0 * * *",
    max_active_runs=1,
    catchup=False,
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

load_raw_sub_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load-incremental-tables-to-data-lake-raw",
    dag=main_dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH
            + "load_incremental_tables_into_data_lake_raw.py",
            "parameters": [ENV, SOURCE, DATA_LAKE_BUCKET, "{{ ds }}"],
        }
    },
)

create_cluster_task >> load_raw_sub_task >> terminate_cluster_task
