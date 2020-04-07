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

SOURCE = "terminator"
DAG_ID = "bietlejuice.{}".format(SOURCE)
ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")

local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 1, 1, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"

# Job params
SOURCE_SCHEMA = "public"

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = S3_PREFIX + "/spark_jobs/{}/".format(SOURCE)

LOAD_DATA_TO_RAW_FILE_PATH = f"{SPARK_JOBS_PATH}load_data_to_raw.py"
CREATE_EXTERNAL_TABLES_FILE_PATH = f"{SPARK_JOBS_PATH}create_external_tables.py"
CREATE_CLEAN_TABLE_IN_DATA_LAKE_PATH = (
    f"{SPARK_JOBS_PATH}create_clean_table_in_datalake.py"
)

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), SOURCE
)

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)


def build_table_sub_dag(
    sub_dag_name,
    env,
    source,
    schema,
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
                    f"{table_name}",
                ],
            }
        },
    )

    clean_table_task >> create_clean_external_tables_task

    return table_sub_dag


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

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

load_data_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load-data-to-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_DATA_TO_RAW_FILE_PATH,
            "parameters": [ENV, DATALAKE_BUCKET],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

file_list = FileService.list_raw_to_clean_sql_files(SOURCE, SOURCE_SCHEMA)
for file_name in file_list:
    file_name = FileService.remove_file_extension(file_name)
    slugged_file_name = file_name.replace("_", "-")
    table_sub_dag = BaseSubDAG.get_sub_dag_operator(
        dag=dag,
        sub_dag_name=f"load-{SOURCE_SCHEMA}-{slugged_file_name}",
        sub_dag_func=build_table_sub_dag,
        env=ENV,
        source=SOURCE,
        schema=SOURCE_SCHEMA,
        table_name=file_name,
        main_dag_id=DAG_ID,
        main_schedule_interval=MAIN_SCHEDULE_INTERVAL,
        main_start_date=MAIN_START_DATE,
    )
    load_data_to_raw_task >> table_sub_dag >> terminate_cluster_task

create_cluster_task >> load_data_to_raw_task
if not file_list:
    load_data_to_raw_task >> terminate_cluster_task
