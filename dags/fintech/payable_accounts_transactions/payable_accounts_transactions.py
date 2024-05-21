from airflow.utils.helpers import chain
from datetime import datetime
import pendulum
import os

from airflow.models import DAG
from airflow.utils.helpers import cross_downstream
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2022, 5, 18, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 3 * * *"

SOURCE = "payable_accounts_transactions"
DAG_ID = f"bietlejuice.{SOURCE}"
ENV = os.environ.get("ENVIRONMENT")


config_service = ConfigurationService(SOURCE)
datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
CUSTOM_SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/"

cluster_description = config_service.get_config("databricks_10_4_min_general_cluster")

LIBRARIES_DESCRIPTION = config_service.get_config("default_libraries")
artifacts_bucket = config_service.get_config("artifacts_bucket")
GDRIVE_ROOT_FOLDER_ID = config_service.get_config("gdrive_root_folder_id")
TABLE_NAME = config_service.get_config("table_name")
COLUMNS_TO_READ = config_service.get_config("columns_to_read")

libraries_description = [
    *LIBRARIES_DESCRIPTION,
    *config_service.get_config("cluster_extra_libs"),
]
libraries_description[2]["whl"] = libraries_description[2]["whl"].format(
    artifacts_bucket=artifacts_bucket
)
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]


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

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=libraries_description,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=SOURCE,
    spark_jobs_path=SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)

raw_task_group = task_group.build_raw_task_group_for_single_table(
    source=SOURCE,
    table_name=TABLE_NAME,
    target_database_base_name=SOURCE,
    extraction_spark_job_file=f"{CUSTOM_SPARK_JOB_PATH}/load_sheets_into_datalake.py",
    raw_spark_job_extra_args=[
        SOURCE,
        TABLE_NAME,
        GDRIVE_ROOT_FOLDER_ID,
        str(COLUMNS_TO_READ),
    ],
)

clean_task_group = task_group.build_clean_task_group(
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    table_name=TABLE_NAME,
)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_group),
    DatalakeTaskGroup.first_tasks(clean_task_group),
)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
