from datetime import datetime
import pendulum
import os
import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.base.datalake_sub_dag import DatalakeSubDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import FileService

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG params setup
SOURCE = "ramo_sap"
DAG_ID = f"bietlejuice.{SOURCE}"
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2020, 11, 24, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 5 * * *"

# s3 paths setup
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_RAMO_BUCKET = Variable.get("ramo_sap_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

SAP_DATA_PATH = f"s3://{S3_RAMO_BUCKET}/razao"
LOAD_SAP_INTO_DATALAKE_RAW_FILE_PATH = (
    S3_PREFIX + f"/spark_jobs/{SOURCE}/load_incremental_data_into_datalake_raw.py"
)
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{DAG_ID}"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"

# cluster setup
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

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
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

table_name = "razao_sap"
slugged_table_name = table_name.replace("_", "-")

ramo_sap_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="ramo-sap-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_SAP_INTO_DATALAKE_RAW_FILE_PATH,
            "parameters": [
                ENV,
                SOURCE,
                DATALAKE_BUCKET,
                SAP_DATA_PATH,
                table_name,
                "{{ ds }}",
            ],
        }
    },
)

sync_metastore_raw_table_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"sync-{slugged_table_name}-hive-metastore-raw-table",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "sync_metastore_tables.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.RAW.value,
                SOURCE,
                "--table-name",
                table_name,
            ],
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
    spark_job_paths=SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

file_list = FileService.list_sql_files_without_extension_from_layer(
    SOURCE, LayerEnum.CLEAN.value
)

clean_sub_dags = clean_sub_dag.build_subdags_from_sql_files(
    dag, file_list, is_incremental=True, partitions=["year", "month", "day"]
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

airflow_helpers.chain(
    create_cluster_task,
    ramo_sap_datalake_raw_task,
    sync_metastore_raw_table_task,
    terminate_cluster_task,
)
ramo_sap_datalake_raw_task >> list(clean_sub_dags.values()) >> terminate_cluster_task
