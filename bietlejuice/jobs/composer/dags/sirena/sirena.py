from datetime import datetime

import pendulum
import os
from airflow.utils import helpers as airflow_helpers
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


ENV = os.environ.get("ENVIRONMENT")

SOURCE = "sirena"
DAG_NAME = f"{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 11, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "30 2 * * *"

ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_default_bucket")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{DAG_NAME}"
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{DAG_NAME}"

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
CUSTOM_LIBRARIES = [
    {
        "whl": f"{ARTIFACTS_S3_BUCKET}/sirena-api-client-python/"
        f"quintoandar_sirena_api_client-0.1.0-py2.py3-none-any.whl"
    }
]

# config vars
CONFIGS_FILE_PATH = (
    f"{os.path.dirname(os.path.realpath(__file__))}/{SOURCE}_config.yaml"
)
CONFIGS_FILE = FileService.get_dict_from_yaml_file(CONFIGS_FILE_PATH)

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
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=CUSTOM_LIBRARIES,
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
    relative_query_path=DAG_NAME,
    spark_job_paths=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
    execution_timeout_hours=1,
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

# Creating sub dags
for config in CONFIGS_FILE["endpoints"]:
    endpoint = config["endpoint"]
    extraction_type = config["extraction_type"]
    if extraction_type == "full":
        raw_parameters = [ENV, SOURCE, DATALAKE_BUCKET, endpoint]
    else:
        raw_parameters = [ENV, SOURCE, DATALAKE_BUCKET, endpoint, "{{ds}}"]

    load_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{extraction_type}-sirena-{endpoint}-to-raw",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/load_sirena_{endpoint}_into_datalake.py",
                "parameters": raw_parameters,
            }
        },
    )

    sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"sync-hive-metastore-sirena-{endpoint}",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables.py",
                "parameters": [
                    DATALAKE_BUCKET,
                    LayerEnum.RAW.value,
                    SOURCE,
                    "--table-name",
                    f"{endpoint}",
                ],
            }
        },
    )

    airflow_helpers.chain(
        load_to_raw_task, sync_metastore_table_task, terminate_cluster_task
    )

    airflow_helpers.chain(
        create_cluster_task,
        load_to_raw_task,
        clean_sub_dags_dict.pop(f"{endpoint}"),
        terminate_cluster_task,
    )
