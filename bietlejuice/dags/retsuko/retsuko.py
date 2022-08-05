from airflow.utils.helpers import chain, cross_downstream
from datetime import datetime
import pendulum
import os

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

from bietlejuice.dags.base.datalake_task_group import DatalakeTaskGroup

from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.airflow import BaseDAG, DAGOwnerEnum


SOURCE = "retsuko"
CONTEXT = SOURCE

DAG_NAME = CONTEXT
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
config_service = ConfigurationService(DAG_NAME)
DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = config_service.get_config("athena_query_results_bucket")
DOC_MD_BASE_URL = config_service.get_config("doc_md_chart_url")

S3_PREFIX = config_service.get_config("databricks_bietlejuice_repo_path")
BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/{DAG_NAME}/load_retsuko_into_datalake.py"

SPARK_JOBS_LOGS_PATH = config_service.get_config("spark_jobs_logs_path")
LOGS_OUTPUT_PATH = f"{SPARK_JOBS_LOGS_PATH}/{DAG_ID}"

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_retsuko", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

LIBRARIES_DESCRIPTION = config_service.get_config("default_libraries")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 1, 25, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 8 * * *"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FINTECH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=LIBRARIES_DESCRIPTION,
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
    source=CONTEXT,
    target_database_base_name=CONTEXT,
    extraction_spark_job_file=RAW_SPARK_JOB_PATH,
)

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_group),
    DatalakeTaskGroup.all_first_tasks(clean_task_groups),
)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
