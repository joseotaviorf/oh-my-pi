from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG

# DAG info setup
SOURCE = "godfather"
SCHEMAS = ["business", "audit"]
ENV = Variable.get("environment")
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time

# S3 paths setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = S3_PREFIX + "/spark_jobs/{}/".format(SOURCE)
LOAD_DB_SCHEMA_INTO_DATALAKE_RAW_FILE_PATH = (
    SPARK_JOBS_PATH + "load_db_schema_into_datalake.py"
)
CREATE_ALL_RAW_EXTERNAL_TABLES_IN_SCHEMA_FILE_PATH = (
    SPARK_JOBS_PATH + "create_all_raw_external_tables_in_schema.py"
)
LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), SOURCE
)

# cluster setup
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

# DAG definition
dag = DAG(
    dag_id="bietlejuice.{}".format(SOURCE),
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime(2019, 10, 1, 0, 0, 0, tzinfo=local_tz),
    schedule_interval="0 1 * * *",
    max_active_runs=1,
    catchup=False,
)


# task builders
def create_load_db_schema_into_datalake_task(source, schema):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="{}-{}-to-datalake-raw".format(source, schema),
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": LOAD_DB_SCHEMA_INTO_DATALAKE_RAW_FILE_PATH,
                "parameters": [ENV, source, schema],
            }
        },
    )


def create_all_raw_external_in_schema_task(source, schema):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-all-raw-external-tables-in-{}".format(schema),
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": CREATE_ALL_RAW_EXTERNAL_TABLES_IN_SCHEMA_FILE_PATH,
                "parameters": [ENV, source, schema],
            }
        },
    )


# Tasks definition
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

load_tasks = [
    create_load_db_schema_into_datalake_task(SOURCE, schema) for schema in SCHEMAS
]

external_tables_tasks = [
    create_all_raw_external_in_schema_task(SOURCE, schema) for schema in SCHEMAS
]

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

# Tasks dependencies definition
create_cluster_task >> load_tasks

for load_task, external_table_task in zip(load_tasks, external_tables_tasks):
    load_task >> external_table_task

external_tables_tasks >> terminate_cluster_task
