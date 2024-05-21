import os
from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

ENV = os.environ.get("ENVIRONMENT")

# DAG params setup
SOURCE = "jira"
CONTEXT = SOURCE

DAG_ID = f"bietlejuice.{CONTEXT}"
local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 6, 1, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"

config_service = ConfigurationService(SOURCE)
# s3 paths setup
ATHENA_QUERY_RESULT_LOCATION = config_service.get_config("athena_query_results_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
S3_PREFIX = config_service.get_config("databricks_bietlejuice_repo_path")

DOC_MD_BASE_URL = config_service.get_config("doc_md_chart_url")

BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"

# cluster setup
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_9_1_med_general_cluster", deserialize_json=True
)

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

CUSTOM_LIBRARIES = [
    {
        "whl": f"{artifacts_bucket}/jira-api-client-python/"
        f"quintoandar_jira_api_client-0.2.1-py2.py3-none-any.whl"
    }
]

# Job params
JOB_PARAMS = [
    {"endpoint_name": "projects", "extraction_type": "full"},
    {"endpoint_name": "issues", "extraction_type": "incremental"},
]


# Dag definition
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GOVERNANCE,
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
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
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
for job_param in JOB_PARAMS:
    endpoint_name = job_param["endpoint_name"]
    extraction_type = job_param["extraction_type"]

    RAW_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/{CONTEXT}/load_{extraction_type}_data_into_datalake_raw.py"
    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        table_name=endpoint_name,
        target_database_base_name=CONTEXT,
        extraction_spark_job_file=RAW_SPARK_JOB_PATH,
        raw_spark_job_extra_args=[CONTEXT, "{{ ds }}", endpoint_name],
    )
    raw_task_groups[endpoint_name] = raw_task_group

incremental_clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
    schema="incremental",  # TODO: we are misusing the schema here: incremental mode is not a schema
    is_incremental=True,
    partitions=["year", "month", "day"],
)

full_clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
    schema="full",  # TODO: we are misusing the schema here: full mode is not a schema
)

clean_task_groups = {**incremental_clean_task_groups, **full_clean_task_groups}

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups))

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
