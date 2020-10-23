from datetime import datetime
import pendulum

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG

SOURCE = "metabase"

# airflow vars
ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

# spark and databricks vars
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{SOURCE}"
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_metabase_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# dag vars
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2020, 7, 27, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"

local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time

# every table to be loaded must be here, with its SQL file name and extraction type
JOBS_EXTRACTION_TYPE = [
    {"table_name": "core_user", "extraction_type": "incremental"},
    {"table_name": "metabase_database", "extraction_type": "incremental"},
    {"table_name": "metabase_field", "extraction_type": "incremental"},
    {"table_name": "metabase_table", "extraction_type": "incremental"},
    {"table_name": "pulse", "extraction_type": "incremental"},
    {"table_name": "pulse_channel", "extraction_type": "incremental"},
    {"table_name": "report_card", "extraction_type": "incremental"},
    {"table_name": "report_dashboard", "extraction_type": "incremental"},
    {"table_name": "report_dashboard_card", "extraction_type": "incremental"},
    {"table_name": "collection", "extraction_type": "full"},
    {"table_name": "pulse_card", "extraction_type": "full"},
    {"table_name": "pulse_channel_recipient", "extraction_type": "full"},
    {"table_name": "query", "extraction_type": "full"},
    {"table_name": "query_execution", "extraction_type": "full"},
    {"table_name": "revision", "extraction_type": "full"},
    {"table_name": "view_log", "extraction_type": "full"},
]

# task builders


def create_tables_sub_dag(sub_dag_name, table_name, extraction_type):
    tables_sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    slugged_table_name = table_name.replace("_", "-")

    load_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{slugged_table_name}-to-raw",
        dag=tables_sub_dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}load_{extraction_type}_data_into_datalake_raw.py",
                "parameters": [ENV, SOURCE, DATALAKE_BUCKET, "{{ ds }}", table_name],
            }
        },
    )

    load_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{slugged_table_name}-to-clean",
        dag=tables_sub_dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}load_{extraction_type}_data_into_datalake_clean.py",
                "parameters": [ENV, SOURCE, DATALAKE_BUCKET, "{{ ds }}", table_name],
            }
        },
    )

    create_clean_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"create-{slugged_table_name}-clean-external-table",
        dag=tables_sub_dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}create_external_table.py",
                "parameters": [
                    ENV,
                    SOURCE,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                    "{{ ds }}",
                    table_name,
                    extraction_type,
                ],
            }
        },
    )

    load_to_raw_task >> load_to_clean_task >> create_clean_external_table_task
    return tables_sub_dag


# dag definition
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

# creating sub dags
for job_extraction_type in JOBS_EXTRACTION_TYPE:
    tables_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
        dag=dag,
        sub_dag_name=job_extraction_type["table_name"],
        sub_dag_func=create_tables_sub_dag,
        table_name=job_extraction_type["table_name"],
        extraction_type=job_extraction_type["extraction_type"],
    )
    create_cluster_task >> tables_sub_dag_task >> terminate_cluster_task
