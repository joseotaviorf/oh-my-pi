from datetime import datetime

import pendulum
import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.airflow import BaseDAG

SOURCE = "heimdall"
TABLE_NAME = "activity"
DAG_ID = f"bietlejuice.{SOURCE}"
ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), SOURCE
)

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_minimum_resources_cluster", deserialize_json=True
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

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "30 4 * * *"

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

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

heimdall_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="heimdall-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "load_heimdall_into_datalake.py",
            "parameters": [ENV, DATALAKE_BUCKET],
        }
    },
)

create_raw_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-raw-external-tables",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "create_raw_external_tables.py",
            "parameters": [ENV, DATALAKE_BUCKET, ATHENA_QUERY_RESULT_LOCATION],
        }
    },
)

sync_metastore_raw_table_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-raw-tables",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOB_PATH + "sync_metastore_tables.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.RAW.value,
                SOURCE,
                "--table-name",
                TABLE_NAME,
            ],
        }
    },
)

validate_sync_metastore_raw_table_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id="validate-sync-hive-metastore-table",
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOB_PATH + "validate_sync_metastore_tables.py",
            "parameters": [LayerEnum.RAW.value, SOURCE, "--table-name", TABLE_NAME],
        }
    },
)

create_clean_table_in_datalake = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create_clean_table_in_datalake",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "create_clean_table_in_datalake.py",
            "parameters": ["heimdall", ENV, DATALAKE_BUCKET, SOURCE],
        }
    },
)

create_clean_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-clean-external-table",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "create_clean_external_table.py",
            "parameters": [ENV, DATALAKE_BUCKET, ATHENA_QUERY_RESULT_LOCATION],
        }
    },
)

sync_metastore_clean_table_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-tables",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOB_PATH + "sync_metastore_tables.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--table-name",
                TABLE_NAME,
            ],
        }
    },
)

validate_sync_metastore_clean_table_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id="validate-sync-hive-metastore-clean-table",
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOB_PATH + "validate_sync_metastore_tables.py",
            "parameters": [LayerEnum.CLEAN.value, SOURCE, "--table-name", TABLE_NAME],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

airflow_helpers.chain(
    create_cluster_task,
    heimdall_to_datalake_raw_task,
    create_raw_external_tables_task,
    create_clean_table_in_datalake,
    create_clean_external_table_task,
    terminate_cluster_task,
)

airflow_helpers.chain(
    heimdall_to_datalake_raw_task,
    sync_metastore_raw_table_task,
    validate_sync_metastore_raw_table_task,
    terminate_cluster_task,
)

airflow_helpers.chain(
    create_clean_table_in_datalake,
    sync_metastore_clean_table_task,
    validate_sync_metastore_clean_table_task,
    terminate_cluster_task,
)
