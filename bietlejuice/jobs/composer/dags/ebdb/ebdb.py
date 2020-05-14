from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG
from bietlejuice.jobs.composer.services.file_service import FileService

# DAG params
DAG_ID = "ebdb"
FULL_DAG_ID = "bietlejuice.{}".format(DAG_ID)
ENV = Variable.get("environment")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 22 * * *"

# Job params
SOURCE = "ebdb"
DW_SCHEMA = "public_spark"
DW_BUCKET = Variable.get("dw_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")

# s3 path setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = S3_PREFIX + "/spark_jobs/{}/".format(DAG_ID)
LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
CREATE_CLEAN_TABLE_IN_DATA_LAKE_PATH = (
    SPARK_JOBS_PATH + "create_clean_table_in_datalake.py"
)
CREATE_EXTERNAL_TABLES_FILE_PATH = SPARK_JOBS_PATH + "create_external_tables.py"
LOAD_DB_SCHEMA_INTO_DATALAKE_RAW_FILE_PATH = (
    SPARK_JOBS_PATH + "load_ebdb_into_datalake.py"
)

# cluster params
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
CLUSTER_DESCRIPTION["num_workers"] = 6

# cluster libraries
DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {
        "jar": f"{ARTIFACTS_S3_BUCKET}/mysql-connector-java/mysql-connector-java-5.1"
        f".47.jar"
    }
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

# dag definition
dag = DAG(
    dag_id=FULL_DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    catchup=False,
)


# methods to create tasks and subdags
def create_clean_table_in_datalake_task(local_dag, table_name, source, env, dag_name):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-clean-{}-in-datalake".format(table_name.replace("_", "-")),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_clean_table_in_datalake.py",
                "parameters": [table_name, source, env, DATALAKE_BUCKET, dag_name],
            }
        },
    )


def create_dw_table_in_datalake_task(local_dag, table_name, schema, env, dag_name):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-dw-{}-{}-in-datalake".format(
            schema, table_name.replace("_", "-")
        ),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_dw_table_in_datalake.py",
                "parameters": [table_name, DW_BUCKET, schema, env, dag_name],
            }
        },
    )


def load_dw_table_into_redshift_task(local_dag, table_name, schema, env):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="load-dw-{}-{}-in-datalake".format(
            schema, table_name.replace("_", "-")
        ),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "load_dw_table_into_redshift.py",
                "parameters": [SPECTRUM_IAM_ROLE, table_name, DW_BUCKET, schema, env],
            }
        },
    )


def create_external_tables_task(local_dag, env, datalake_layer, source, tables):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-{}-external-tables".format(datalake_layer),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_external_tables.py",
                "parameters": [
                    env,
                    ATHENA_QUERY_RESULT_LOCATION,
                    datalake_layer,
                    DATALAKE_BUCKET,
                    source,
                    "--tables",
                ]
                + tables,
            }
        },
    )


def create_clean_and_dim_tables_sub_dag(sub_dag_name, dw_schema, dim_table):
    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=FULL_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()
    dim_table_task = create_dw_table_in_datalake_task(
        local_dag, dim_table, dw_schema, ENV, DAG_ID
    )
    load_dim_table_task = load_dw_table_into_redshift_task(
        local_dag, dim_table, dw_schema, ENV
    )

    dim_table_task >> load_dim_table_task

    return local_dag


def build_table_sub_dag(
    sub_dag_name,
    env,
    source,
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

    clean_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=table_sub_dag,
        task_id=f"create-clean-{slugged_table_name}-in-data-lake",
        json={
            "spark_python_task": {
                "python_file": CREATE_CLEAN_TABLE_IN_DATA_LAKE_PATH,
                "parameters": [
                    table_name,
                    source,
                    env,
                    DATALAKE_BUCKET,
                    DAG_ID,
                    "clean",
                ],
            }
        },
    )

    create_clean_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=table_sub_dag,
        task_id=f"create-{slugged_table_name}-clean-external-table",
        pool="athena",
        json={
            "spark_python_task": {
                "python_file": CREATE_EXTERNAL_TABLES_FILE_PATH,
                "parameters": [
                    env,
                    ATHENA_QUERY_RESULT_LOCATION,
                    "clean",
                    DATALAKE_BUCKET,
                    source,
                    "--tables",
                ]
                + [table_name],
            }
        },
    )
    clean_table_task >> create_clean_external_tables_task
    return table_sub_dag


def create_raw_tables_sub_dag_tasks(
    sub_dag_name, source, full_dag_id, schedule_interval, start_date
):
    local_raw_sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=full_dag_id,
        schedule_interval=schedule_interval,
        start_date=start_date,
    )._build_local_dag()

    load_tables_into_datalake_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="load-tables-to-datalake-raw",
        dag=local_raw_sub_dag,
        json={
            "spark_python_task": {
                "python_file": LOAD_DB_SCHEMA_INTO_DATALAKE_RAW_FILE_PATH,
                "parameters": [ENV, DATALAKE_BUCKET],
            }
        },
    )

    create_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-all-raw-external-tables",
        dag=local_raw_sub_dag,
        pool="athena",
        json={
            "spark_python_task": {
                "python_file": CREATE_EXTERNAL_TABLES_FILE_PATH,
                "parameters": [
                    ENV,
                    ATHENA_QUERY_RESULT_LOCATION,
                    "raw",
                    DATALAKE_BUCKET,
                    source,
                    "--all",
                ],
            }
        },
    )

    load_tables_into_datalake_task >> create_external_tables_task
    return local_raw_sub_dag


# tasks and subdags definitions
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

polygon_region_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id="polygon_region_to_datalake_raw",
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "load_query_table_in_datalake.py",
            "parameters": [ENV, DATALAKE_BUCKET, "poligonoregiao", SOURCE],
        }
    },
)

condo_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="dim_condo",
    sub_dag_func=create_clean_and_dim_tables_sub_dag,
    dw_schema=DW_SCHEMA,
    dim_table="dim_condo",
)

region_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="dim_region",
    sub_dag_func=create_clean_and_dim_tables_sub_dag,
    dw_schema=DW_SCHEMA,
    dim_table="dim_region",
)

visit_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="dim_visit",
    sub_dag_func=create_clean_and_dim_tables_sub_dag,
    dw_schema=DW_SCHEMA,
    dim_table="dim_visit",
)

inspection_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="dim_inspection",
    sub_dag_func=create_clean_and_dim_tables_sub_dag,
    dw_schema=DW_SCHEMA,
    dim_table="dim_inspection",
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

load_raw_sub_dag = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="load-tables-to-datalake-raw",
    sub_dag_func=create_raw_tables_sub_dag_tasks,
    source=SOURCE,
    full_dag_id=FULL_DAG_ID,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    start_date=MAIN_START_DATE,
)

file_list = FileService.list_layer_sql_files(SOURCE, "clean")
for file_name in file_list:
    file_name = FileService.remove_file_extension(file_name)
    slugged_file_name = file_name.replace("_", "-")
    table_sub_dag = BaseSubDAG.get_sub_dag_operator(
        dag=dag,
        sub_dag_name=f"load-{slugged_file_name}",
        sub_dag_func=build_table_sub_dag,
        env=ENV,
        source=SOURCE,
        table_name=file_name,
        main_dag_id=FULL_DAG_ID,
        main_schedule_interval=MAIN_SCHEDULE_INTERVAL,
        main_start_date=MAIN_START_DATE,
    )

    # this statement is necessary cuz polygon_region needs to run an specific query to raw schema
    if slugged_file_name == "polygon-region":
        polygon_region_to_datalake_raw_task >> table_sub_dag
    elif slugged_file_name == "condo":
        table_sub_dag >> condo_sub_dag_task
    elif slugged_file_name == "region":
        table_sub_dag >> region_sub_dag_task
    elif slugged_file_name == "visit":
        table_sub_dag >> visit_sub_dag_task
    elif slugged_file_name == "inspection":
        table_sub_dag >> inspection_sub_dag_task
    load_raw_sub_dag >> table_sub_dag >> terminate_cluster_task
create_cluster_task >> [load_raw_sub_dag, polygon_region_to_datalake_raw_task]
[
    condo_sub_dag_task,
    region_sub_dag_task,
    visit_sub_dag_task,
    inspection_sub_dag_task,
] >> terminate_cluster_task
