from datetime import datetime
import json

import pendulum
import os

from airflow.models import DAG
from airflow.utils.helpers import chain, cross_downstream
from airflow.operators.databricks_plugin import (
    QuintoAndarDatabricksExecuteJobClusterOperator,
    QuintoAndarDatabricksCheckJobTaskOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group_job_cluster import (
    DatalakeTaskGroupJobCluster,
)
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

SOURCE = "invoice_preview"
CONTEXT = SOURCE
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(SOURCE)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 11, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "00 8 * * *"

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
CUSTOM_SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/"

CLUSTER_DESCRIPTION = config_service.get_config("databricks_10_4_min_general_cluster")
CLUSTER_DESCRIPTION["spark_env_vars"]["ENVIRONMENT"] = ENV
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{spark_jobs_logs_path}{DAG_ID}"
LIBRARIES_DESCRIPTION = config_service.get_config("default_libraries")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

SOURCE_ROOT_PATH = config_service.get_config("source_root_path")
TABLE_NAME = config_service.get_config("table_name")
CONSUMER_EXTRA_ARGS = config_service.get_config("consumer_extra_args")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FINTECH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

execute_job_cluster_task = QuintoAndarDatabricksExecuteJobClusterOperator(
    dag=dag,
    task_id="execute-job-cluster",
    databricks_conn_id="databricks_job_cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=LIBRARIES_DESCRIPTION,
)

task_group = DatalakeTaskGroupJobCluster(
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
    target_database_base_name=SOURCE,
    extraction_spark_job_file=f"{CUSTOM_SPARK_JOB_PATH}/load_csv_into_datalake.py",
    raw_spark_job_extra_args=[
        SOURCE,
        SOURCE_ROOT_PATH,
        "{{ ds }}",
        TABLE_NAME,
        json.dumps(CONSUMER_EXTRA_ARGS),
    ],
)


check_data = QuintoAndarDatabricksCheckJobTaskOperator(
    databricks_conn_id="databricks_job_cluster",
    dag=dag,
    task_id=f"check-completion-notify",
    json={
        "spark_python_task": {
            "python_file": f"{CUSTOM_SPARK_JOB_PATH}/check_completion_notify.py",
            "parameters": [ENV, datalake_bucket, SOURCE, TABLE_NAME, "{{ds}}"],
        }
    },
)


partition_columns = config_service.get_config("partition_cols")
clean_task_group = task_group.build_clean_task_group(
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    table_name=TABLE_NAME,
    is_incremental=False,
    partitions=partition_columns,
)


chain(execute_job_cluster_task, DatalakeTaskGroupJobCluster.first_tasks(raw_task_group))
cross_downstream(
    DatalakeTaskGroupJobCluster.last_tasks(raw_task_group),
    DatalakeTaskGroupJobCluster.first_tasks(clean_task_group),
)
chain(DatalakeTaskGroupJobCluster.last_tasks(clean_task_group), check_data)
