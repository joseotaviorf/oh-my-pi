from datetime import datetime
import os
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

# airflow vars
ENV = os.environ.get("ENVIRONMENT")
DAG_NAME = "rental_guarantee"
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

# spark and databricks vars
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{DAG_NAME}"
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# dag vars
DAG_ID = f"bietlejuice.{DAG_NAME}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2020, 7, 27, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 6 * * *"
CONFIGS_FILE_PATH = f"{os.path.dirname(os.path.realpath(__file__))}/{DAG_NAME}.config"

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


create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

configs_file = FileService.get_dict_from_yaml_file(CONFIGS_FILE_PATH)

raw_tasks = {}
raw_to_clean = {}

for table in configs_file:
    table_name = table["table_name"]
    slugged_table_name = table_name.replace("_", "-")
    extraction_type = table["extraction_type"]
    raw_to_clean[table_name] = table.get("clean_table_name", table_name)

    parameters = [ENV, DATALAKE_BUCKET, DAG_NAME, table_name]
    if extraction_type == "incremental":
        parameters.append(table["date_filter_column"])
        parameters.append(table.get("unixtime_measure", "date"))
        parameters.append("{{ ds }}")

    raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{extraction_type}-{slugged_table_name}-to-raw",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": S3_PREFIX
                + f"/spark_jobs/{DAG_NAME}/load_{extraction_type}_tables_into_datalake_raw.py",
                "parameters": parameters,
            }
        },
    )

    airflow_helpers.chain(create_cluster_task, raw_task)
    raw_tasks[table_name] = raw_task

sync_metastore_raw_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"sync-{slugged_table_name}-hive-metastore-raw-table",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "sync_metastore_tables.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.RAW.value,
                DAG_NAME,
                "--all-tables",
            ],
        }
    },
)

validate_sync_metastore_raw_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"validate-{slugged_table_name}-sync-hive-metastore-raw-table",
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "validate_sync_metastore_tables.py",
            "parameters": [LayerEnum.RAW.value, DAG_NAME, "--all-tables"],
        }
    },
)

airflow_helpers.chain(
    list(raw_tasks.values()),
    sync_metastore_raw_tables_task,
    validate_sync_metastore_raw_tables_task,
    terminate_cluster_task,
)

# [END] Raw layer sub dags

clean_sub_dag = DatalakeSubDAG(
    dag_id=DAG_ID,
    start_date=MAIN_START_DATE,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    layer=LayerEnum.CLEAN,
    database_base_name=DAG_NAME,
    relative_query_path=DAG_NAME,
    spark_job_paths=SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

file_list_full = FileService.list_sql_files_without_extension_from_layer(
    DAG_NAME, LayerEnum.CLEAN.value, schema="full"
)

file_list_incremental = FileService.list_sql_files_without_extension_from_layer(
    DAG_NAME, LayerEnum.CLEAN.value, schema="incremental"
)

clean_sub_dags_full = clean_sub_dag.build_subdags_from_sql_files(
    dag, file_list_full, schema="full"
)
clean_sub_dags_incremental = clean_sub_dag.build_subdags_from_sql_files(
    dag,
    file_list_incremental,
    is_incremental=True,
    partitions=["year", "month", "day"],
    schema="incremental",
)

clean_sub_dags_dict = {**clean_sub_dags_full, **clean_sub_dags_incremental}


# DAG FLOW:

for table_name, raw_task in raw_tasks.items():
    clean_table_name = raw_to_clean.get(table_name)
    if clean_sub_dags_dict.get(clean_table_name):
        airflow_helpers.chain(
            raw_task, clean_sub_dags_dict.get(clean_table_name), terminate_cluster_task
        )
