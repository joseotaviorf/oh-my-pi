from datetime import datetime

import pendulum
import os
from airflow.utils import helpers as airflow_helpers
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup


ENV = os.environ.get("ENVIRONMENT")

SOURCE = "braze_analytics"
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 11, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "30 0 * * *"

ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_default_bucket")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{SOURCE}"
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = (
    f"{S3_PREFIX}/spark_jobs/{SOURCE}/load_braze_analytics_into_datalake.py"
)

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
CUSTOM_LIBRARIES = [
    {
        "whl": f"{ARTIFACTS_S3_BUCKET}/braze-api-client-python/"
        f"quintoandar_braze_api_client-0.1.0-py2.py3-none-any.whl"
    }
]

APP_GROUPS = ["owners", "tenants"]
IDENTIFIERS = ["campaign", "canvas"]
PARTITION_COLS = ["year", "month", "day"]

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
    libraries=CUSTOM_LIBRARIES,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    relative_query_path=SOURCE,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

raw_task_groups = {}
for app_group in APP_GROUPS:
    for identifier in IDENTIFIERS:
        parameters = [SOURCE, app_group, identifier, "{{ds}}"]
        table_name = table_name = f"{identifier}_analytics_{app_group}"
        raw_task_group = task_group.build_raw_task_group_for_single_table(
            source=SOURCE,
            table_name=table_name,
            target_database_base_name=SOURCE,
            extraction_spark_job_file=RAW_SPARK_JOB_PATH,
            raw_spark_job_extra_args=parameters,
        )
        raw_task_groups[table_name] = raw_task_group

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    is_incremental=True,
    partitions=PARTITION_COLS,
)

airflow_helpers.chain(
    create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups)
)

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
