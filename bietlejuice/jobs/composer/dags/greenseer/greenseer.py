from datetime import datetime
import pendulum
import os
import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup

SOURCE = "greenseer"

# airflow vars
ENV = os.environ.get("ENVIRONMENT")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

# spark and databricks vars
BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/load_greenseer_into_datalake.py"
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{SOURCE}"
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# dag vars
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2021, 2, 18, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 5 * * *"

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

greenseer_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="greenseer-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": RAW_SPARK_JOB_PATH,
            "parameters": [ENV, DATALAKE_BUCKET, SOURCE],
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

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    relative_query_path=SOURCE,
    spark_jobs_path=BASE_SPARK_JOB_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    is_incremental=False,
)

airflow_helpers.chain(
    create_cluster_task,
    greenseer_to_datalake_raw_task,
    DatalakeTaskGroup.all_first_tasks(clean_task_groups),
)
terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))

airflow_helpers.chain(
    greenseer_to_datalake_raw_task, sync_metastore_tables_task, terminate_cluster_task
)
