from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG

# ENV params setup
from bietlejuice.jobs.composer.services import FileService

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


def build_table_clean_sub_dag(
    sub_dag_name,
    env,
    source,
    data_lake_bucket,
    athena_query_result_location,
    table_name,
    main_dag_id,
    main_schedule_interval,
    main_start_date,
    spark_jobs_path,
):
    table_sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=main_dag_id,
        schedule_interval=main_schedule_interval,
        start_date=main_start_date,
    )._build_local_dag()

    slugged_table_name = table_name.replace("_", "-")

    clean_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=table_sub_dag,
        task_id=f"create-{slugged_table_name}-in-data-lake-clean",
        json={
            "spark_python_task": {
                "python_file": spark_jobs_path
                + "load_incremental_to_datalake_layer.py",
                "parameters": [
                    env,
                    source,
                    data_lake_bucket,
                    "clean",
                    table_name,
                    "{{ ds }}",
                ],
            }
        },
    )

    create_clean_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=table_sub_dag,
        task_id=f"create-{slugged_table_name}-clean-external-table",
        json={
            "spark_python_task": {
                "python_file": spark_jobs_path + "create_external_tables.py",
                "parameters": [
                    env,
                    data_lake_bucket,
                    athena_query_result_location,
                    "clean",
                    source,
                    "{{ ds }}",
                    table_name,
                ],
            }
        },
    )

    clean_table_task >> create_clean_external_tables_task
    return table_sub_dag


# Create clean tasks from clean SQLs
clean_sub_dags_list = []
file_list = FileService.list_raw_to_clean_sql_files(SOURCE)
for file_name in file_list:
    file_name = FileService.remove_file_extension(file_name)
    slugged_file_name = file_name.replace("_", "-")
    table_sub_dag = BaseSubDAG.get_sub_dag_operator(
        dag=main_dag,
        sub_dag_name=f"load-{slugged_file_name}-to-clean",
        sub_dag_func=build_table_clean_sub_dag,
        env=ENV,
        source=SOURCE,
        data_lake_bucket=DATALAKE_BUCKET,
        athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
        table_name=file_name,
        main_dag_id=DAG_ID,
        main_schedule_interval=MAIN_SCHEDULE_INTERVAL,
        main_start_date=MAIN_START_DATE,
        spark_jobs_path=SPARK_JOBS_PATH,
    )
    clean_sub_dags_list.append(table_sub_dag)

create_cluster_task >> load_raw_table

if clean_sub_dags_list:
    load_raw_table.set_downstream(clean_sub_dags_list)
    clean_sub_dags_list >> terminate_cluster_task
else:
    load_raw_table >> terminate_cluster_task
