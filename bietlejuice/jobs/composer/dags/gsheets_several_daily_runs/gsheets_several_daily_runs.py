import os
import pendulum
import json
import pytz
from datetime import datetime

from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.operators.python_operator import ShortCircuitOperator

from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import FileService


def check_run_hour(schedule_hours, dag_execution_date):
    if schedule_hours == "always":
        return True

    brt_tz = pytz.timezone("America/Sao_Paulo")
    current_time_utc = datetime.strptime(dag_execution_date[:-6], "%Y-%m-%dT%H:%M:%S")
    current_time_brt = current_time_utc.replace(tzinfo=pytz.utc).astimezone(brt_tz)
    current_hour = current_time_brt.hour
    return str(current_hour) in schedule_hours.split(",")


# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG params setup
SOURCE = "gsheets"
CONTEXT = "gsheets_several_daily_runs"
DAG_ID = f"bietlejuice.{CONTEXT}"
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2021, 1, 14, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 1,9,11,17 * * *"

# Task params
TASK_POOL = "gsheets_several_daily_runs_pool"

# s3 paths setup
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_default_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{DAG_ID}"
RAW_SPARK_JOB_PATH = (
    S3_PREFIX + f"/spark_jobs/{CONTEXT}/load_full_data_into_datalake_raw.py"
)

# cluster setup
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

CUSTOM_LIBRARIES = [
    {
        "whl": f"{ARTIFACTS_S3_BUCKET}/gsheets-api-client-python/"
        f"quintoandar_gsheets_api_client-0.1.0-py2.py3-none-any.whl"
    }
]

GOOGLE_FILES_YAML_PATH = os.path.join(
    os.path.dirname(os.path.realpath(__file__)),
    "gsheets_several_daily_runs_files.yaml"
    # TODO we could encapsulate this into some service like ServiceBla.get_current_dag_dir()
)

GOOGLE_FILES = FileService.get_dict_from_yaml_file(GOOGLE_FILES_YAML_PATH)

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
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
    relative_query_path=CONTEXT,
    spark_jobs_path=BASE_SPARK_JOB_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

raw_task_groups = {}
skip_run_tasks = {}
for table_name, sheet_details in GOOGLE_FILES.items():

    skip_run_task = ShortCircuitOperator(
        task_id=f"check-hour-to-skip-{table_name}",
        python_callable=check_run_hour,
        op_kwargs={
            "schedule_hours": sheet_details.get("schedule_hours", "always"),
            "dag_execution_date": "{{ts}}",
        },
    )
    skip_run_tasks[table_name] = skip_run_task

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        extraction_spark_job_file=RAW_SPARK_JOB_PATH,
        raw_spark_job_extra_args=[SOURCE, table_name, json.dumps(sheet_details)],
        pool=TASK_POOL,
    )
    raw_task_groups[sheet_details["clean_table_name"]] = raw_task_group

    create_cluster_task >> skip_run_task >> DatalakeTaskGroup.first_tasks(
        raw_task_group
    )


clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
)

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
