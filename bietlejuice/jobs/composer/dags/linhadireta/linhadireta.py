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
from bietlejuice.jobs.composer.dags.linhadireta import SOURCE

DAG_ID = f"bietlejuice.{SOURCE}"
ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
DATABRICKS_S3_BUCKET = Variable.get("databricks_s3_bucket")

LOAD_LINHADIRETA_INTO_DATALAKE_RAW_FILE_PATH = (
    S3_PREFIX + f"/spark_jobs/{SOURCE}/load_linhadireta_into_datalake.py"
)
CREATE_CLEAN_TABLE_IN_DATALAKE_FILE_PATH = (
    S3_PREFIX + f"/spark_jobs/{SOURCE}/create_clean_table_in_datalake.py"
)
CREATE_CLEAN_EXTERNAL_TABLES_FILE_PATH = (
    S3_PREFIX + f"/spark_jobs/{SOURCE}/create_clean_external_tables.py"
)

LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_S3_BUCKET}/logs/jobs/{SOURCE}"
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_linha_direta", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

# dag params
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"

local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID),
)


def clean_tasks(sub_dag_name, table_name, slugged_table_name):
    sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    load_clean_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"create-clean-{slugged_table_name}-in-data-lake",
        json={
            "spark_python_task": {
                "python_file": CREATE_CLEAN_TABLE_IN_DATALAKE_FILE_PATH,
                "parameters": [table_name, ENV, DATALAKE_BUCKET],
            }
        },
    )

    create_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"create-clean-external-{slugged_table_name}-table",
        json={
            "spark_python_task": {
                "python_file": CREATE_CLEAN_EXTERNAL_TABLES_FILE_PATH,
                "parameters": [
                    table_name,
                    ENV,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                ],
            }
        },
    )

    load_clean_table_task >> create_external_table_task

    return sub_dag


def build_clean_subdags(prev_task, next_task):
    # create subdag for each clean table
    file_list = FileService.list_layer_sql_files(SOURCE, "clean")

    if file_list:
        for file_name in file_list:
            file_name = FileService.remove_file_extension(file_name)
            slugged_table_name = file_name.replace("_", "-")
            table_sub_dag = BaseSubDAG.get_sub_dag_operator(
                dag=dag,
                sub_dag_name=f"load-{slugged_table_name}-to-datalake-clean",
                sub_dag_func=clean_tasks,
                table_name=file_name,
                slugged_table_name=slugged_table_name,
            )
            prev_task >> table_sub_dag >> next_task
    else:
        prev_task >> next_task


create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

linhadireta_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="linhadireta-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_LINHADIRETA_INTO_DATALAKE_RAW_FILE_PATH,
            "parameters": [ENV, DATALAKE_BUCKET],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)


create_cluster_task >> linhadireta_to_datalake_raw_task
build_clean_subdags(linhadireta_to_datalake_raw_task, terminate_cluster_task)
