from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.dags.cidade_alerta import (
    QUERIES_CIDADE_ALERTA_DATALAKE_PATH,
    INCREMENTAL_TABLES,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG
from bietlejuice.jobs.composer.services import FileService

DAG_NAME = "cidade_alerta"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_cidade_alerta", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {
        "maven": {
            "coordinates": "org.mongodb.spark:mongo-spark-connector_2.11:2.4.0",
            "repo": "https://mvnrepository.com/artifact/org.mongodb.spark/mongo-spark-connector",
        }
    }
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

# bietlejuice paths
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{DAG_NAME}/"

# dag params
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2020, 1, 21, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "30 5 * * *"

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


def clean_full_tasks(sub_dag_name, table_name, slugged_table_name):
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
                "python_file": SPARK_JOBS_PATH
                + "create_clean_full_table_in_datalake.py",
                "parameters": [table_name, ENV, DATALAKE_BUCKET],
            }
        },
    )

    create_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"create-clean-external-{slugged_table_name}-table",
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_clean_external_full_table.py",
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


def clean_incremental_tasks(sub_dag_name, table_name, slugged_table_name):

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
                "python_file": SPARK_JOBS_PATH
                + "create_clean_incremental_table_in_datalake.py",
                "parameters": [table_name, ENV, DATALAKE_BUCKET, "{{ ds }}"],
            }
        },
    )

    create_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"create-clean-external-{slugged_table_name}-table",
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH
                + "create_clean_external_incremental_table.py",
                "parameters": [
                    table_name,
                    ENV,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                    "{{ ds }}",
                ],
            }
        },
    )

    load_clean_table_task >> create_external_table_task

    return sub_dag


def get_sub_dag_object(file_name, stage, mode):

    slugged_table_name = file_name.replace("_", "-")

    table_sub_dag = BaseSubDAG.get_sub_dag_operator(
        dag=dag,
        sub_dag_name=f"{mode}-load-{slugged_table_name}-to-{stage}",
        sub_dag_func=eval(f"{stage}_{mode}_tasks"),
        table_name=file_name,
        slugged_table_name=slugged_table_name,
    )

    return table_sub_dag


def build_sub_dags(stage):

    # create sub_dag for each table
    file_list = FileService.list_files(f"{QUERIES_CIDADE_ALERTA_DATALAKE_PATH}/{stage}")
    incremental_sub_dags = {}
    full_sub_dags = {}

    for file_name in file_list:
        file_name = FileService.remove_file_extension(file_name)

        if file_name in INCREMENTAL_TABLES:
            incremental_sub_dags[file_name] = get_sub_dag_object(
                file_name=file_name, stage=stage, mode="incremental"
            )
        else:
            full_sub_dags[file_name] = get_sub_dag_object(
                file_name=file_name, stage=stage, mode="full"
            )

    # incremental_sub_dags and full_sub_dags are dicts where the keys are table or file names
    # and the values are corresponding sub_dag objects
    return full_sub_dags, incremental_sub_dags


create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

load_full_tables_into_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load-full-tables-into-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "load_full_tables_into_datalake_raw.py",
            "parameters": [ENV, DATALAKE_BUCKET],
        }
    },
)

load_incremental_tables_into_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load-incremental-tables-into-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH
            + "load_incremental_tables_into_datalake_raw.py",
            "parameters": [ENV, DATALAKE_BUCKET, "{{ ds }}"],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> [
    load_full_tables_into_datalake_raw_task,
    load_incremental_tables_into_datalake_raw_task,
]

clean_full_sub_dags, clean_incremental_sub_dags = build_sub_dags("clean")

load_incremental_tables_into_datalake_raw_task >> list(
    clean_incremental_sub_dags.values()
) >> terminate_cluster_task

load_full_tables_into_datalake_raw_task >> list(
    clean_full_sub_dags.values()
) >> terminate_cluster_task
