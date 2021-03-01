from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG

# DAG params
from bietlejuice.jobs.composer.services.file_service import FileService

DAG_ID = "godfather"
FULL_DAG_ID = f"bietlejuice.{DAG_ID}"
ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 10, 1, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"

# Job params
SOURCE = "godfather"
SOURCE_SCHEMAS = ["business", "audit"]
DW_SCHEMA = "public_spark"

# S3 paths setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = S3_PREFIX + "/spark_jobs/{}/".format(SOURCE)
LOAD_DB_SCHEMA_INTO_DATALAKE_RAW_FILE_PATH = (
    f"{SPARK_JOBS_PATH}load_db_schema_into_datalake.py"
)
CREATE_EXTERNAL_TABLES_FILE_PATH = f"{SPARK_JOBS_PATH}create_external_tables.py"
CREATE_CLEAN_TABLE_IN_DATA_LAKE_PATH = (
    f"{SPARK_JOBS_PATH}create_clean_table_in_datalake.py"
)

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), SOURCE
)

# cluster setup
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_godfather", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

# DAG definition
DAG = DAG(
    dag_id=FULL_DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=DOC_MD_BASE_URL, dag_id=FULL_DAG_ID
    ),
)


# Task builders
def create_raw_tables_sub_dag_tasks(
    sub_dag_name, source, schema, full_dag_id, schedule_interval, start_date
):
    local_raw_sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=full_dag_id,
        schedule_interval=schedule_interval,
        start_date=start_date,
    )._build_local_dag()

    load_tables_into_datalake_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="load-{}-tables-to-datalake-raw".format(schema),
        dag=local_raw_sub_dag,
        json={
            "spark_python_task": {
                "python_file": LOAD_DB_SCHEMA_INTO_DATALAKE_RAW_FILE_PATH,
                "parameters": [ENV, DATALAKE_BUCKET, source, schema],
            }
        },
    )

    create_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-all-{}-raw-external-tables".format(schema),
        dag=local_raw_sub_dag,
        json={
            "spark_python_task": {
                "python_file": CREATE_EXTERNAL_TABLES_FILE_PATH,
                "parameters": [
                    ENV,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                    "raw",
                    SOURCE,
                    schema,
                    "--all",
                ],
            }
        },
    )

    load_tables_into_datalake_task >> create_external_tables_task

    return local_raw_sub_dag


def build_table_sub_dag(
    sub_dag_name,
    env,
    source,
    schema,
    table_name,
    main_dag_id,
    main_schedule_interval,
    main_start_date,
    dw_schema,
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
        task_id=f"create-clean-{slugged_table_name}-in-data-lake",
        json={
            "spark_python_task": {
                "python_file": CREATE_CLEAN_TABLE_IN_DATA_LAKE_PATH,
                "parameters": [table_name, env, DATALAKE_BUCKET, source, schema],
            }
        },
    )

    create_clean_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=table_sub_dag,
        task_id=f"create-{slugged_table_name}-clean-external-table",
        json={
            "spark_python_task": {
                "python_file": CREATE_EXTERNAL_TABLES_FILE_PATH,
                "parameters": [
                    env,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                    "clean",
                    source,
                    schema,
                    "--tables",
                    f"{schema}_{table_name}",
                ],
            }
        },
    )

    clean_table_task >> create_clean_external_tables_task

    # Todo: implement dim_task. Will be done on next PR

    return table_sub_dag


# Tasks definition
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=DAG,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=DAG, task_id="terminate-cluster"
)

# Create Raw, Clean and Dim tasks
load_raw_tasks_list = []
for schema in SOURCE_SCHEMAS:
    load_raw_sub_dag = BaseSubDAG.get_sub_dag_operator(
        dag=DAG,
        sub_dag_name="load-{}-tables-to-datalake-raw".format(schema),
        sub_dag_func=create_raw_tables_sub_dag_tasks,
        source=SOURCE,
        schema=schema,
        full_dag_id=FULL_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )
    load_raw_tasks_list.append(load_raw_sub_dag)

    file_list = FileService.list_layer_sql_files(SOURCE, "clean", schema)
    for file_name in file_list:
        file_name = FileService.remove_file_extension(file_name)
        slugged_file_name = file_name.replace("_", "-")
        table_sub_dag = BaseSubDAG.get_sub_dag_operator(
            dag=DAG,
            sub_dag_name=f"load-{schema}-{slugged_file_name}",
            sub_dag_func=build_table_sub_dag,
            env=ENV,
            source=SOURCE,
            schema=schema,
            table_name=file_name,
            dw_schema=DW_SCHEMA,
            main_dag_id=FULL_DAG_ID,
            main_schedule_interval=MAIN_SCHEDULE_INTERVAL,
            main_start_date=MAIN_START_DATE,
        )
        load_raw_sub_dag >> table_sub_dag >> terminate_cluster_task

    create_cluster_task >> load_raw_sub_dag
    if not file_list:
        load_raw_sub_dag >> terminate_cluster_task
