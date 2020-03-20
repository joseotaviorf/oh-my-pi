from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG
from bietlejuice.jobs.composer.services import FileService

# ENV params setup
ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")

# DAG params setup
SOURCE = "autodialer"
DAG_ID = f"bietlejuice.{SOURCE}"
sp_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 3, 16, 0, 0, 0, tzinfo=sp_tz)
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"

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


# Functions definitions
def build_table_sub_dag(
    sub_dag_name,
    env,
    source,
    data_lake_bucket,
    table_name,
    main_dag_id,
    main_schedule_interval,
    main_start_date,
):
    table_sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=main_dag_id,
        schedule_interval=main_schedule_interval,
        start_date=main_start_date,
    )._build_local_dag()
    slugged_table_name = table_name.replace("_", "-")

    QuintoAndarDatabricksSubmitRunOperator(
        dag=table_sub_dag,
        task_id=f"create-clean-{slugged_table_name}-in-data-lake",
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH
                + "load_incremental_tables_into_data_lake_clean.py",
                "parameters": [table_name, env, data_lake_bucket, source, "{{ ds }}"],
            }
        },
    )

    # TODO: create_clean_external_tables_task
    #  clean_table_task >> create_clean_external_tables_task

    return table_sub_dag


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

# Create Raw and Clean tasks
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

file_list = FileService.list_raw_to_clean_sql_files(SOURCE)
for file_name in file_list:
    file_name = FileService.remove_file_extension(file_name)
    slugged_file_name = file_name.replace("_", "-")
    table_sub_dag = BaseSubDAG.get_sub_dag_operator(
        dag=main_dag,
        sub_dag_name=f"load-{slugged_file_name}",
        sub_dag_func=build_table_sub_dag,
        env=ENV,
        source=SOURCE,
        data_lake_bucket=DATALAKE_BUCKET,
        table_name=file_name,
        main_dag_id=DAG_ID,
        main_schedule_interval=MAIN_SCHEDULE_INTERVAL,
        main_start_date=MAIN_START_DATE,
    )
    load_raw_sub_task >> table_sub_dag >> terminate_cluster_task

create_cluster_task >> load_raw_sub_task
if not file_list:
    load_raw_sub_task >> terminate_cluster_task
