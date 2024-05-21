import os
from datetime import datetime
import pendulum

from airflow.utils.helpers import chain, cross_downstream
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

# dag vars
SOURCE = "batch_inference"
CONTEXT = SOURCE
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(SOURCE)
partition_cols = config_service.get_config("partition_cols")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")


DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2023, 3, 13, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 7 * * *"

SOURCE_ROOT_PATH = config_service.get_config("source_root_path")
TABLE_NAME = config_service.get_config("table_name")

BASE_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs"
BASE_SPARK_JOBS_PATH = f"{BASE_PATH}/base/"
RAW_SPARK_JOB_PATH = f"{BASE_PATH}/{SOURCE}/"
RAW_SPARK_JOB_FILE = f"{RAW_SPARK_JOB_PATH}/load_parquet_into_datalake.py"

default_libraries = config_service.get_config("default_libraries")
cluster_description = config_service.get_config("databricks_10_4_med_general_cluster")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.DATA_PRODUCTS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.MLOPS,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=CONTEXT,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)

raw_task_group = task_group.build_raw_task_group_for_single_table(
    source=SOURCE,
    table_name=TABLE_NAME,
    target_database_base_name=CONTEXT,
    extraction_spark_job_file=RAW_SPARK_JOB_FILE,
    raw_spark_job_extra_args=[
        SOURCE,
        SOURCE_ROOT_PATH,
        "{{ ds }}",
        TABLE_NAME,
    ],
)

partition_columns = config_service.get_config("partition_cols")
clean_task_group = task_group.build_clean_task_group(
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    table_name=TABLE_NAME,
    is_incremental=True,
    partitions=partition_columns,
)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_group),
    DatalakeTaskGroup.first_tasks(clean_task_group)
)

chain(DatalakeTaskGroup.last_tasks(clean_task_group), terminate_cluster_task)
