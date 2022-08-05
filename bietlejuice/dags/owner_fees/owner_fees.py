import os
from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain

from bietlejuice.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services import FileService
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

SOURCE = "owner_fees"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{CONTEXT}"

# airflow vars
ENV = os.environ.get("ENVIRONMENT")
config_service = ConfigurationService(SOURCE)
DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = config_service.get_config("athena_query_results_bucket")
SPARK_JOBS_LOGS_PATH = config_service.get_config("spark_jobs_logs_path")
S3_PREFIX = config_service.get_config("databricks_bietlejuice_repo_path")
DOC_MD_BASE_URL = config_service.get_config("doc_md_chart_url")

# spark and databricks vars
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"
LOGS_OUTPUT_PATH = f"{SPARK_JOBS_LOGS_PATH}/{DAG_ID}"
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
default_libraries = config_service.get_config("default_libraries")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

# dag vars
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2020, 8, 10, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 5 * * *"
CONFIGS_FILE_PATH = f"{os.path.dirname(os.path.realpath(__file__))}/owner_fees.config"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FINTECH,
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
    libraries=default_libraries,
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
configs_file = FileService.get_dict_from_yaml_file(CONFIGS_FILE_PATH)
for table in configs_file:
    table_name = table["table_name"]
    extraction_type = table["extraction_type"]
    parameters = [CONTEXT, table_name]

    if extraction_type == "incremental":
        parameters.extend([table["date_filter_column"], "{{ ds }}"])

    RAW_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/{CONTEXT}/load_{extraction_type}_data_into_datalake_raw.py"
    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        table_name=table_name,
        target_database_base_name=CONTEXT,
        extraction_spark_job_file=RAW_SPARK_JOB_PATH,
        raw_spark_job_extra_args=parameters,
    )
    raw_task_groups[table_name] = raw_task_group

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
