from datetime import datetime
import pendulum

from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG

# ENV setup
from bietlejuice.jobs.composer.base.pipeline import LayerEnum

ENV = Variable.get("environment")

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
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{DAG_ID}"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

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


# Task builders
def create_endpoint_sub_dag(sub_dag_name, endpoint_name, extraction_type):
    endpoint_sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    load_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{endpoint_name}-to-raw",
        dag=endpoint_sub_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH
                + f"load_{extraction_type}_data_into_datalake_raw.py",
                "parameters": [ENV, SOURCE, DATALAKE_BUCKET, "{{ ds }}", endpoint_name],
            }
        },
    )

    sync_metastore_raw_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"sync-hive-metastore-raw-table",
        dag=endpoint_sub_dag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables.py",
                "parameters": [
                    DATALAKE_BUCKET,
                    LayerEnum.RAW.value,
                    SOURCE,
                    "--table-name",
                    endpoint_name,
                ],
            }
        },
    )

    validate_sync_metastore_raw_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=endpoint_sub_dag,
        task_id="validate-sync-hive-metastore-raw-table",
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH
                + "validate_sync_metastore_tables.py",
                "parameters": [
                    LayerEnum.RAW.value,
                    SOURCE,
                    "--table-name",
                    endpoint_name,
                ],
            }
        },
    )

    load_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{endpoint_name}-to-clean",
        dag=endpoint_sub_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH
                + f"load_{extraction_type}_data_into_datalake_clean.py",
                "parameters": [ENV, SOURCE, DATALAKE_BUCKET, "{{ ds }}", endpoint_name],
            }
        },
    )

    create_clean_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"create-{endpoint_name}-clean-external-table",
        dag=endpoint_sub_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH
                + f"create_{extraction_type}_external_table.py",
                "parameters": [
                    ENV,
                    SOURCE,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                    "{{ ds }}",
                    endpoint_name,
                ],
            }
        },
    )

    sync_metastore_clean_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"sync-hive-metastore-clean-table",
        dag=endpoint_sub_dag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables.py",
                "parameters": [
                    DATALAKE_BUCKET,
                    LayerEnum.CLEAN.value,
                    SOURCE,
                    "--table-name",
                    endpoint_name,
                ],
            }
        },
    )

    validate_sync_metastore_clean_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=endpoint_sub_dag,
        task_id="validate-sync-hive-metastore-clean-table",
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH
                + "validate_sync_metastore_tables.py",
                "parameters": [
                    LayerEnum.CLEAN.value,
                    SOURCE,
                    "--table-name",
                    endpoint_name,
                ],
            }
        },
    )

    load_to_raw_task >> load_to_clean_task >> create_clean_external_table_task
    load_to_raw_task >> sync_metastore_raw_table_task >> validate_sync_metastore_raw_table_task
    load_to_clean_task >> sync_metastore_clean_table_task >> validate_sync_metastore_clean_table_task
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
for job_param in JOB_PARAMS:
    endpoint_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
        dag=dag,
        sub_dag_name=job_param["endpoint_name"],
        sub_dag_func=create_endpoint_sub_dag,
        endpoint_name=job_param["endpoint_name"],
        extraction_type=job_param["extraction_type"],
    )
    create_cluster_task >> endpoint_sub_dag_task >> terminate_cluster_task
