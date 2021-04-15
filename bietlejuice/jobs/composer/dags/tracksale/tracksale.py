from datetime import datetime
import pendulum

from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG

# ENV setup
ENV = Variable.get("environment")

# DAG params setup
SOURCE = "tracksale"
DAG_ID = f"bietlejuice.{SOURCE}"
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 6, 1, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"

# s3 paths setup
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{DAG_ID}"
BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

# cluster setup
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_tracksale", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {
        "whl": f"{ARTIFACTS_S3_BUCKET}/tracksale-api-client-python/"
        f"quintoandar_tracksale_api_client-0.2.0-py2.py3-none-any.whl"
    }
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

# Job params
ENDPOINTS = {"answer": "incremental", "campaign": "full", "dispatch": "incremental"}

# If the column is a MapType, use a dot to set the path to the Campaign ID column
CAMPAIGN_COLUMN = {
    "answer": "campaign_code",
    "campaign": "code",
    "dispatch": "campaign.code",
}

# If more than one Campaing ID need to be blocked, separate them by comma
CAMPAIGNS_TO_BLOCK = "248"


# Task builders
def create_endpoint_sub_dag(
    sub_dag_name, endpoint, ingestion, dag_configs, campaign_column, campaigns_to_block
):
    endpoint_sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=dag_configs.get("main_dag_id"),
        schedule_interval=dag_configs.get("main_schedule_interval"),
        start_date=dag_configs.get("main_start_date"),
    )._build_local_dag()

    load_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{endpoint}-to-raw",
        dag=endpoint_sub_dag,
        json={
            "spark_python_task": {
                "python_file": dag_configs.get("spark_jobs_path")
                + f"load_{ingestion}_data_into_datalake_raw.py",
                "parameters": [
                    dag_configs.get("env"),
                    dag_configs.get("source"),
                    dag_configs.get("datalake_bucket"),
                    "{{ ds }}",
                    endpoint,
                    campaign_column,
                    campaigns_to_block,
                ],
            }
        },
    )

    load_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{endpoint}-to-clean",
        dag=endpoint_sub_dag,
        json={
            "spark_python_task": {
                "python_file": dag_configs.get("spark_jobs_path")
                + f"load_{ingestion}_data_into_datalake_clean.py",
                "parameters": [
                    dag_configs.get("env"),
                    dag_configs.get("source"),
                    dag_configs.get("datalake_bucket"),
                    "{{ ds }}",
                    endpoint,
                ],
            }
        },
    )

    create_clean_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"create-{endpoint}-clean-external-table",
        dag=endpoint_sub_dag,
        json={
            "spark_python_task": {
                "python_file": dag_configs.get("spark_jobs_path")
                + f"create_{ingestion}_external_table.py",
                "parameters": [
                    dag_configs.get("env"),
                    dag_configs.get("source"),
                    dag_configs.get("datalake_bucket"),
                    dag_configs.get("athena_query_result_location"),
                    "{{ ds }}",
                    endpoint,
                ],
            }
        },
    )

    sync_metastore_raw_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="sync-hive-metastore-raw-table",
        dag=endpoint_sub_dag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOB_PATH + "sync_metastore_tables.py",
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

    validate_sync_raw_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=endpoint_sub_dag,
        task_id="validate-sync-hive-metastore-raw-table",
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOB_PATH
                + "validate_sync_metastore_tables.py",
                "parameters": [LayerEnum.RAW.value, SOURCE, "--table-name", endpoint],
            }
        },
    )

    sync_metastore_clean_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="sync-hive-metastore-clean-table",
        dag=endpoint_sub_dag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOB_PATH + "sync_metastore_tables.py",
                "parameters": [
                    DATALAKE_BUCKET,
                    LayerEnum.CLEAN.value,
                    SOURCE,
                    "--table-name",
                    endpoint,
                ],
            }
        },
    )

    validate_sync_clean_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=endpoint_sub_dag,
        task_id="validate-sync-hive-metastore-clean-table",
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOB_PATH
                + "validate_sync_metastore_tables.py",
                "parameters": [LayerEnum.CLEAN.value, SOURCE, "--table-name", endpoint],
            }
        },
    )

    load_to_raw_task >> load_to_clean_task >> create_clean_external_table_task

    load_to_raw_task >> sync_metastore_raw_table_task >> validate_sync_raw_table_task

    load_to_clean_task >> sync_metastore_clean_table_task >> validate_sync_clean_table_task

    return endpoint_sub_dag


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

# Creating sub dags
for endpoint, ingestion in ENDPOINTS.items():
    endpoint_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
        dag=dag,
        sub_dag_name=endpoint,
        sub_dag_func=create_endpoint_sub_dag,
        endpoint=endpoint,
        ingestion=ingestion,
        campaign_column=CAMPAIGN_COLUMN[endpoint],
        campaigns_to_block=CAMPAIGNS_TO_BLOCK,
        dag_configs={
            "env": ENV,
            "source": SOURCE,
            "datalake_bucket": DATALAKE_BUCKET,
            "athena_query_result_location": ATHENA_QUERY_RESULT_LOCATION,
            "main_dag_id": DAG_ID,
            "main_schedule_interval": MAIN_SCHEDULE_INTERVAL,
            "main_start_date": MAIN_START_DATE,
            "spark_jobs_path": SPARK_JOBS_PATH,
        },
    )

    create_cluster_task >> endpoint_sub_dag_task >> terminate_cluster_task
