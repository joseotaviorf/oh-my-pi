import os
from pendulum import timezone
import json
from datetime import datetime

from airflow.models import DAG
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services import FileService
from bietlejuice.base.airflow.helpers import TaskFlowHelper

from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

# DAG params setup
SOURCE = "marketing_offline_costs"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{CONTEXT}"
# use cron expressions in local time
MAIN_START_DATE = datetime(2021, 10, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "55 6 * * *"

CLUSTER_DESCRIPTION = "databricks_10_4_min_general_cluster"
config_service = ConfigurationService(SOURCE)

# s3 paths setup
ATHENA_QUERY_RESULT_LOCATION = config_service.get_config("athena_query_results_bucket")
ARTIFACTS_S3_BUCKET = config_service.get_config("artifacts_bucket")
DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
DOC_MD_BASE_URL = config_service.get_config("doc_md_chart_url")
S3_PREFIX = config_service.get_config("databricks_bietlejuice_repo_path")
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/"
LOAD_GSHEETS_INTO_DATALAKE_RAW_FILE_PATH = (
    f"{BASE_SPARK_JOBS_PATH}load_gsheets_into_datalake_raw.py"
)
BASE_LOG_PATH = config_service.get_config("spark_jobs_logs_path")
LOGS_OUTPUT_PATH = f"{BASE_LOG_PATH}{DAG_ID}"

# cluster setup
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")

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

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
ENV = os.environ.get("ENVIRONMENT")

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
    cluster_configuration=cluster_configuration,
    libraries=default_libraries + CUSTOM_LIBRARIES,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
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
    has_create_external_table_task=False,
)

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups))

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
