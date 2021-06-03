from datetime import datetime

import pendulum
import os

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG
from bietlejuice.jobs.composer.services import FileService

# DAG params
SOURCE = "wall_street"
DAG_ID = f"bietlejuice.{SOURCE}"
ENV = os.environ.get("ENVIRONMENT")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 6 * * *"
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

# Job params
DATALAKE_BUCKET = Variable.get("datalake_bucket")

# s3 path setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOBS_PATH = S3_PREFIX + f"/spark_jobs/{SOURCE}/"
LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), SOURCE
)
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")

# cluster params
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# cluster libraries
DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {
        "jar": f"{ARTIFACTS_S3_BUCKET}/mysql-connector-java/mysql-connector-java-5.1"
        ".47.jar"
    }
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

# dag definition
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
                "python_file": SPARK_JOBS_PATH + "create_clean_table_in_datalake.py",
                "parameters": [table_name, ENV, DATALAKE_BUCKET, SOURCE],
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
                    SOURCE,
                ],
            }
        },
    )

    sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="sync-hive-metastore-clean-tables",
        dag=sub_dag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOB_PATH + "sync_metastore_tables.py",
                "parameters": [
                    DATALAKE_BUCKET,
                    LayerEnum.CLEAN.value,
                    SOURCE,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    load_clean_table_task.set_downstream(
        [create_external_table_task, sync_metastore_table_task]
    )

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


load_tables_into_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load-tables-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "load_wall_street_into_datalake.py",
            "parameters": [ENV, DATALAKE_BUCKET, SOURCE],
        }
    },
)

sync_metastore_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-raw-tables",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOB_PATH + "sync_metastore_tables.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.RAW.value,
                SOURCE,
                "--all-tables",
            ],
        }
    },
)

# tasks definitions
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)


airflow_helpers.chain(
    create_cluster_task,
    load_tables_into_datalake_raw_task,
    sync_metastore_tables_task,
    terminate_cluster_task,
)

build_clean_subdags(load_tables_into_datalake_raw_task, terminate_cluster_task)
