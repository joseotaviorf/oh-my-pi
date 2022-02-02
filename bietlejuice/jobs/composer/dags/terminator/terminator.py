import os
from datetime import datetime

import airflow.utils.helpers as airflow_helpers
import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup

SOURCE = "terminator"
CONTEXT = SOURCE

# airflow vars
ENV = os.environ.get("ENVIRONMENT")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

# spark and databricks vars
BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/{CONTEXT}/load_data_to_raw.py"
SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/"
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{CONTEXT}"
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_terminator", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# DAG vars
DAG_ID = f"bietlejuice.{CONTEXT}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 1, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 3 * * *"
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(CONTEXT).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    relative_query_path=CONTEXT,
    spark_jobs_path=BASE_SPARK_JOB_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

raw_task_group = task_group.build_raw_task_group_for_all_tables(
    source=SOURCE,
    target_database_base_name=CONTEXT,
    extraction_spark_job_file=RAW_SPARK_JOB_PATH,
)

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
)

airflow_helpers.chain(
    create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group)
)

airflow_helpers.cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_group),
    DatalakeTaskGroup.all_first_tasks(clean_task_groups),
)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
