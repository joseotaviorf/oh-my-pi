from datetime import datetime
import pendulum
import os

from airflow.utils.helpers import chain
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG params setup
SOURCE = "tracksale"
DAG_ID = f"bietlejuice.{SOURCE}"
config_service = ConfigurationService(SOURCE)
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 6, 1, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 2 * * *"

# s3 paths setup
ATHENA_QUERY_RESULT_LOCATION = config_service.get_config("athena_query_results_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
S3_PREFIX = config_service.get_config("databricks_bietlejuice_repo_path")
DOC_MD_BASE_URL = config_service.get_config("doc_md_chart_url")

BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"

cluster_description = config_service.get_config("databricks_12_2_min_general_cluster")
default_libraries = config_service.get_config("default_libraries")
dag_documentation = config_service.get_config("dag_documentation")

CUSTOM_LIBRARIES = [
    {
        "whl": f"{artifacts_bucket}/tracksale-api-client-python/"
        f"quintoandar_tracksale_api_client-0.3.0-py2.py3-none-any.whl"
    }
]
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
DAG_OWNER = DAGOwnerEnum.DATA_SS

# Job params
ENDPOINTS = {"answer": "incremental", "campaign": "full", "dispatch": "incremental"}

# If the column is a MapType, use a dot to set the path to the Campaign ID column
CAMPAIGN_COLUMN = {
    "answer": "campaign_code",
    "campaign": "code",
    "dispatch": "campaign.code",
}

# If more than one Campaing ID need to be blocked, separate them by comma
CAMPAIGNS_TO_BLOCK = "248,326,327,356"


# Dag definition
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=SOURCE,
        doc_md_chart_url=DOC_MD_BASE_URL,
        dag_documentation=dag_documentation,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        dag_owner=DAG_OWNER,
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries + CUSTOM_LIBRARIES,
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
for endpoint, ingestion in ENDPOINTS.items():
    parameters = [SOURCE, endpoint, CAMPAIGN_COLUMN[endpoint], CAMPAIGNS_TO_BLOCK]

    if ingestion == "incremental":
        parameters.extend(["{{ ds }}"])

    RAW_SPARK_JOB_PATH = (
        f"{S3_PREFIX}/spark_jobs/{SOURCE}/load_{ingestion}_data_into_datalake_raw.py"
    )
    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        table_name=endpoint,
        target_database_base_name=SOURCE,
        extraction_spark_job_file=RAW_SPARK_JOB_PATH,
        raw_spark_job_extra_args=parameters,
    )
    raw_task_groups[endpoint] = raw_task_group

incremental_clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    schema="incremental",  # TODO: we are misusing the schema here: incremental mode is not a schema
    is_incremental=True,
    partitions=["year", "month", "day"],
)

full_clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    schema="full",  # TODO: we are misusing the schema here: full mode is not a schema
)

clean_task_groups = {**incremental_clean_task_groups, **full_clean_task_groups}

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups))

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))