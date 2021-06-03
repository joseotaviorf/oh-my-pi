from datetime import datetime
import os
import pendulum

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_sub_dag import DatalakeSubDAG
from bietlejuice.jobs.composer.services import FileService


SOURCE = "owner_fees"

# airflow vars
ENV = os.environ.get("ENVIRONMENT")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

# spark and databricks vars
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{SOURCE}"
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# dag vars
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2020, 8, 10, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 5 * * *"
CONFIGS_FILE_PATH = f"{os.path.dirname(os.path.realpath(__file__))}/owner_fees.config"

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

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

# [BEGIN] Raw layer tasks

configs_file = FileService.get_dict_from_yaml_file(CONFIGS_FILE_PATH)

raw_tasks = {}

for table in configs_file:
    table_name = table["table_name"]
    slugged_table_name = table_name.replace("_", "-")
    extraction_type = table["extraction_type"]

    parameters = [ENV, SOURCE, DATALAKE_BUCKET, table_name]
    if extraction_type == "incremental":
        parameters.append(table["date_filter_column"])
        parameters.append("{{ ds }}")

    raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{extraction_type}-{slugged_table_name}-to-raw",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}load_{extraction_type}_data_into_datalake_raw.py",
                "parameters": parameters,
            }
        },
    )

    sync_metastore_raw_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"sync-{slugged_table_name}-hive-metastore-raw-table",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables.py",
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

    chain(
        create_cluster_task,
        raw_task,
        sync_metastore_raw_table_task,
        terminate_cluster_task,
    )
    raw_tasks[table_name] = raw_task

# [END] Raw layer sub dags

# [BEGIN] Clean layer sub dags

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

incr_sql_list = FileService.list_sql_files_without_extension_from_layer(
    SOURCE, LayerEnum.CLEAN.value, schema="incremental"
)

incr_clean_sub_dags = clean_sub_dag.build_subdags_from_sql_files(
    dag,
    incr_sql_list,
    is_incremental=True,
    partitions=["year", "month", "day"],
    schema="incremental",
)

full_sql_list = FileService.list_sql_files_without_extension_from_layer(
    SOURCE, LayerEnum.CLEAN.value, schema="full"
)

full_clean_sub_dags = clean_sub_dag.build_subdags_from_sql_files(
    dag, full_sql_list, is_incremental=False, schema="full"
)

clean_sub_dags_dict = {**incr_clean_sub_dags, **full_clean_sub_dags}

# [END] Clean layer sub dags

for table_name, raw_task in raw_tasks.items():
    if clean_sub_dags_dict.get(table_name):
        raw_task >> clean_sub_dags_dict.get(table_name) >> terminate_cluster_task
