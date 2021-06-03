from datetime import datetime
import pendulum
import os

from airflow.models import DAG, Variable
import airflow.utils.helpers as airflow_helpers
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import FileService

DAG_NAME = "chat_fup"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

# databricks config
LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_chat_fup", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

# bietlejuice paths
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{DAG_NAME}/"
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"

# dag params
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 3 * * *"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
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
                "python_file": SPARK_JOBS_PATH + "create_clean_table_in_datalake.py",
                "parameters": [table_name, ENV, DATALAKE_BUCKET],
            }
        },
    )

    create_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"create-clean-external-{slugged_table_name}-table",
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_clean_external_tables.py",
                "parameters": [
                    table_name,
                    ENV,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                ],
            }
        },
    )

    sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"sync-hive-metastore-table",
        dag=sub_dag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables.py",
                "parameters": [
                    DATALAKE_BUCKET,
                    LayerEnum.CLEAN.value,
                    DAG_NAME,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    validate_sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id="validate-sync-hive-metastore-table",
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH
                + "validate_sync_metastore_tables.py",
                "parameters": [
                    LayerEnum.CLEAN.value,
                    DAG_NAME,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    load_clean_table_task >> create_external_table_task
    load_clean_table_task >> sync_metastore_table_task >> validate_sync_metastore_table_task

    return sub_dag


def build_clean_subdags(prev_task, next_task):
    # create subdag for each clean table
    file_list = FileService.list_layer_sql_files(DAG_NAME, "clean")

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

chat_fup_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="chat-fup-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "load_chat_fup_into_datalake.py",
            "parameters": [ENV, DATALAKE_BUCKET],
        }
    },
)

sync_metastore_raw_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-raw-tables",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.RAW.value,
                DAG_NAME,
                "--all-tables",
            ],
        }
    },
)

validate_sync_metastore_raw_table_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id="validate-sync-hive-metastore-table",
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOBS_PATH + "validate_sync_metastore_tables.py",
            "parameters": [LayerEnum.RAW.value, DAG_NAME, "--all-tables"],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> chat_fup_to_datalake_raw_task
build_clean_subdags(chat_fup_to_datalake_raw_task, terminate_cluster_task)

airflow_helpers.chain(
    chat_fup_to_datalake_raw_task,
    sync_metastore_raw_tables_task,
    validate_sync_metastore_raw_table_task,
    terminate_cluster_task,
)
