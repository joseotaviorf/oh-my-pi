from datetime import datetime

import pendulum
import os

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from airflow.utils.helpers import chain

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import FileService

# ENV params setup
ENV = os.environ.get("ENVIRONMENT")
DATALAKE_BUCKET = Variable.get("datalake_bucket")

# DAG params setup
SOURCE = "autodialer"
DAG_NAME = "autodialer"
DAG_ID = f"bietlejuice.{SOURCE}"
sp_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 3, 16, 0, 0, 0, tzinfo=sp_tz)
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

# S3 paths setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
S3_BUCKET = Variable.get("databricks_s3_bucket")
DATA_LAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"

# cluster setup
LOGS_OUTPUT_PATH = f"s3://{S3_BUCKET}/logs/jobs/{SOURCE}"
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_autodialer", deserialize_json=True
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
        task_id=f"create-clean-{slugged_table_name}-in-data-lake",
        json={
            "spark_python_task": {
                "python_file": spark_jobs_path
                + "load_incremental_tables_into_data_lake_clean.py",
                "parameters": [table_name, env, data_lake_bucket, source, "{{ ds }}"],
            }
        },
    )

    create_clean_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=table_sub_dag,
        task_id=f"create-{slugged_table_name}-clean-external-table",
        json={
            "spark_python_task": {
                "python_file": spark_jobs_path + "create_external_incremental_table.py",
                "parameters": [
                    env,
                    data_lake_bucket,
                    athena_query_result_location,
                    "clean",
                    source,
                    "{{ ds }}",
                    "--tables",
                    f"{table_name}",
                ],
            }
        },
    )

    sync_metastore_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"sync-hive-metastore-table",
        dag=table_sub_dag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables.py",
                "parameters": [
                    data_lake_bucket,
                    LayerEnum.CLEAN.value,
                    source,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    validate_sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=table_sub_dag,
        task_id="validate-sync-hive-metastore-table",
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH
                + "validate_sync_metastore_tables.py",
                "parameters": [
                    LayerEnum.CLEAN.value,
                    source,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    clean_table_task >> sync_metastore_tables_task >> validate_sync_metastore_table_task
    clean_table_task >> create_clean_external_tables_task
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
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
)


# Create tables task builder


def build_raw_sub_dag_tasks(
    sub_dag_name,
    env,
    datalake_bucket,
    athena_query_result_location,
    datalake_layer,
    source,
    full_dag_id,
    schedule_interval,
    start_date,
    spark_jobs_path,
):
    """
    Returns SubDagOperator with its respective dags and subtasks, namely, QuintoAndarDatabricksSubmitRunOperator
    which responsible to create tables in Athena Metastore, as well as, add the partitions when necessary
    :param sub_dag_name: name to identify sub dag name
    :param env: run time env
    :param datalake_bucket: path to datalake_bucket
    :param athena_query_result_location: path to query results in datalake
    :param datalake_layer: clean/raw/... layer
    :param source: integration source
    :param full_dag_id: full name of parent dag
    :param schedule_interval: schedule interval to subdag
    :param start_date: start date to subdag
    :param spark_jobs_path: path to spark job files
    :return: return a SUBDAG operator object with its respective dags and tasks
    """
    local_raw_sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=full_dag_id,
        schedule_interval=schedule_interval,
        start_date=start_date,
    )._build_local_dag()

    create_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-{}-incremental-external-tables".format(datalake_layer),
        dag=local_raw_sub_dag,
        json={
            "spark_python_task": {
                "python_file": spark_jobs_path + "create_external_incremental_table.py",
                "parameters": [
                    env,
                    datalake_bucket,
                    athena_query_result_location,
                    datalake_layer,
                    source,
                    "{{ ds }}",
                    "--all",
                ],
            }
        },
    )

    load_raw_table = QuintoAndarDatabricksSubmitRunOperator(
        task_id="load-incremental-tables-to-data-lake-raw",
        dag=local_raw_sub_dag,
        json={
            "spark_python_task": {
                "python_file": spark_jobs_path
                + "load_incremental_tables_into_data_lake_raw.py",
                "parameters": [env, source, datalake_bucket, "{{ ds }}"],
            }
        },
    )
    load_raw_table >> create_external_table_task
    return local_raw_sub_dag


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

create_raw_sub_tasks = BaseSubDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=build_raw_sub_dag_tasks,
    sub_dag_name=f"load-raw-tables",
    env=ENV,
    datalake_bucket=DATA_LAKE_BUCKET,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
    datalake_layer="raw",
    source=SOURCE,
    full_dag_id=DAG_ID,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    start_date=MAIN_START_DATE,
    spark_jobs_path=SPARK_JOBS_PATH,
)

sync_hive_metastore_raw_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-raw-tables",
    dag=main_dag,
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables.py",
            "parameters": [
                DATA_LAKE_BUCKET,
                LayerEnum.RAW.value,
                SOURCE,
                "--all-tables",
            ],
        }
    },
)

validate_sync_metastore_raw_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=main_dag,
    task_id="validate-sync-hive-metastore-raw-tables",
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOBS_PATH + "validate_sync_metastore_tables.py",
            "parameters": [LayerEnum.RAW.value, SOURCE, "--all-tables"],
        }
    },
)

file_list = FileService.list_layer_sql_files(SOURCE, "clean")
for file_name in file_list:
    file_name = FileService.remove_file_extension(file_name)
    slugged_file_name = file_name.replace("_", "-")
    table_sub_dag = BaseSubDAG.get_sub_dag_operator(
        dag=main_dag,
        sub_dag_name=f"load-clean-{slugged_file_name}",
        sub_dag_func=build_table_sub_dag,
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

    create_raw_sub_tasks >> table_sub_dag >> terminate_cluster_task

chain(
    create_cluster_task,
    create_raw_sub_tasks,
    sync_hive_metastore_raw_tables_task,
    validate_sync_metastore_raw_tables_task,
    terminate_cluster_task,
)

if not file_list:
    create_raw_sub_tasks >> terminate_cluster_task
