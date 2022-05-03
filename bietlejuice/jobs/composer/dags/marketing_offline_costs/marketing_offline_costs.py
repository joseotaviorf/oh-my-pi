import os
import pendulum
import json
from datetime import datetime

from airflow.models import DAG
from airflow.models import Variable
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG params setup
SOURCE = "marketing_offline_costs"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{CONTEXT}"
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2021, 1, 14, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "55 6 * * *"

# s3 paths setup
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_default_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/"
LOAD_GSHEETS_INTO_DATALAKE_RAW_FILE_PATH = (
    f"{BASE_SPARK_JOBS_PATH}load_gsheets_into_datalake_raw.py"
)
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{DAG_ID}"

# cluster setup
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

CUSTOM_LIBRARIES = [
    {
        "whl": f"{ARTIFACTS_S3_BUCKET}/gsheets-api-client-python/"
        f"quintoandar_gsheets_api_client-0.2.1-py2.py3-none-any.whl"
    }
]

GOOGLE_FILES_YAML_PATH = os.path.join(
    os.path.dirname(os.path.realpath(__file__)), "marketing_offline_costs.yaml"
)

GOOGLE_FILES = FileService.get_dict_from_yaml_file(GOOGLE_FILES_YAML_PATH)

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
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
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

raw_task_groups = {}
for TABLE_NAME, SHEET_DETAILS in GOOGLE_FILES.items():

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=TABLE_NAME,
        extraction_spark_job_file=LOAD_GSHEETS_INTO_DATALAKE_RAW_FILE_PATH,
        raw_spark_job_extra_args=[SOURCE, TABLE_NAME, json.dumps(SHEET_DETAILS)],
    )
    raw_task_groups[TABLE_NAME] = raw_task_group


clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
)

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups))

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
