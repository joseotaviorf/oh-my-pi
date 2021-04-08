from datetime import datetime

import pendulum

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_sub_dag import DatalakeSubDAG
from bietlejuice.jobs.composer.services import FileService


SOURCE = "terminator"

# airflow vars
ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

# spark and databricks vars
BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/"
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{SOURCE}"
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_terminator", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

# DAG vars
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 1, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

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

terminator_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load-terminator-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": f"{SPARK_JOB_PATH}/{SOURCE}/load_data_to_raw.py",
            "parameters": [ENV, DATALAKE_BUCKET],
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

validate_sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id="validate-sync-hive-metastore-table",
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOB_PATH + "validate_sync_metastore_tables.py",
            "parameters": [LayerEnum.RAW.value, SOURCE, "--all-tables"],
        }
    },
)

clean_sub_dag = DatalakeSubDAG(
    dag_id=DAG_ID,
    start_date=MAIN_START_DATE,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    layer=LayerEnum.CLEAN,
    database_base_name=SOURCE,
    relative_query_path=SOURCE,
    spark_job_paths=f"{SPARK_JOB_PATH}/base",
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)
file_list = FileService.list_sql_files_without_extension_from_layer(
    SOURCE, LayerEnum.CLEAN.value
)
clean_sub_dags = clean_sub_dag.build_subdags_from_sql_files(dag, file_list)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> terminator_to_datalake_raw_task >> list(
    clean_sub_dags.values()
) >> terminate_cluster_task

airflow_helpers.chain(
    terminator_to_datalake_raw_task,
    sync_metastore_tables_task,
    validate_sync_metastore_table_task,
    terminate_cluster_task,
)
