import os
from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain, cross_downstream

from bietlejuice.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

ENV = os.environ.get("ENVIRONMENT")

# DAG params setup
SOURCE = "monopoly"
CONTEXT = SOURCE

DAG_ID = f"bietlejuice.{CONTEXT}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2021, 6, 17, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 5 * * *"

config_service = ConfigurationService(SOURCE)
# s3 paths setup
DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = config_service.get_config("athena_query_results_bucket")
ARTIFACTS_S3_BUCKET = config_service.get_config("artifacts_bucket")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
S3_PREFIX = config_service.get_config("databricks_bietlejuice_repo_path")
DOC_MD_BASE_URL = config_service.get_config("doc_md_chart_url")
RAW_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/{CONTEXT}/load_{SOURCE}_into_datalake.py"

SPARK_JOBS_LOGS_PATH = config_service.get_config("spark_jobs_logs_path")
LOGS_OUTPUT_PATH = f"{SPARK_JOBS_LOGS_PATH}/{DAG_ID}"
BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"

# cluster setup
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)

CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
default_libraries = config_service.get_config("default_libraries")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

# Dag definition
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

raw_task_group = task_group.build_raw_task_group_for_all_tables(
    source=SOURCE,
    target_database_base_name=CONTEXT,
    extraction_spark_job_file=RAW_SPARK_JOB_PATH,
    raw_spark_job_extra_args=[CONTEXT],
)

clean_task_group = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_group),
    DatalakeTaskGroup.all_first_tasks(clean_task_group),
)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_group))
