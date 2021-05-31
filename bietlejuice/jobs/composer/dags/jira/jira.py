from datetime import datetime
import pendulum
import os

from airflow.models import DAG, Variable
from airflow.utils import helpers as airflow_helpers
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_sub_dag import DatalakeSubDAG

ENV = os.environ.get("ENVIRONMENT")

# DAG params setup
SOURCE = "jira"
DAG_ID = f"bietlejuice.{SOURCE}"
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2020, 6, 1, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"

# s3 paths setup
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{DAG_ID}"
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"


# cluster setup
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_minimum_resources_cluster", deserialize_json=True
)


CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {
        "whl": f"{ARTIFACTS_S3_BUCKET}/jira-api-client-python/"
        f"quintoandar_jira_api_client-0.1.0-py2.py3-none-any.whl"
    }
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

# Job params
JOB_PARAMS = [
    {"endpoint_name": "projects", "extraction_type": "full"},
    {"endpoint_name": "issues", "extraction_type": "incremental"},
]


# Dag definition
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

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

clean_sub_dag = DatalakeSubDAG(
    dag_id=DAG_ID,
    start_date=MAIN_START_DATE,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    layer=LayerEnum.CLEAN,
    database_base_name=SOURCE,
    relative_query_path=SOURCE,
    spark_job_paths=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

incremental_load_file_list = FileService.list_sql_files_without_extension_from_layer(
    SOURCE, LayerEnum.CLEAN.value, schema="incremental"
)
incremental_load_clean_sub_dags = clean_sub_dag.build_subdags_from_sql_files(
    dag,
    incremental_load_file_list,
    is_incremental=True,
    partitions=["year", "month", "day"],
    schema="incremental",
)

full_load_file_list = FileService.list_sql_files_without_extension_from_layer(
    SOURCE, LayerEnum.CLEAN.value, schema="full"
)
full_load_clean_sub_dags = clean_sub_dag.build_subdags_from_sql_files(
    dag, full_load_file_list, schema="full"
)

all_clean_subdags = {**incremental_load_clean_sub_dags, **full_load_clean_sub_dags}

# Creating sub dags
for job_param in JOB_PARAMS:
    endpoint = job_param["endpoint_name"]
    extraction_type = job_param["extraction_type"]

    load_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{endpoint}-to-raw",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}load_{extraction_type}_data_into_datalake_raw.py",
                "parameters": [ENV, SOURCE, DATALAKE_BUCKET, "{{ ds }}", endpoint],
            }
        },
    )

    sync_metastore_raw_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"sync-hive-metastore-{endpoint}-raw-table",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": f"{BASE_SPARK_JOBS_PATH}sync_metastore_tables.py",
                "parameters": [
                    DATALAKE_BUCKET,
                    LayerEnum.RAW.value,
                    SOURCE,
                    "--table-name",
                    endpoint,
                ],
            }
        },
    )

    validate_sync_metastore_raw_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=dag,
        task_id=f"validate-sync-hive-metastore-{endpoint}-raw-table",
        json={
            "spark_python_task": {
                "python_file": f"{BASE_SPARK_JOBS_PATH}validate_sync_metastore_tables.py",
                "parameters": [LayerEnum.RAW.value, SOURCE, "--table-name", endpoint],
            }
        },
    )

    airflow_helpers.chain(
        create_cluster_task,
        load_to_raw_task,
        sync_metastore_raw_table_task,
        validate_sync_metastore_raw_table_task,
        terminate_cluster_task,
    )

    airflow_helpers.chain(
        load_to_raw_task, all_clean_subdags.pop(endpoint), terminate_cluster_task
    )
