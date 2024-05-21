import os
from datetime import datetime

from airflow.models import DAG
from airflow.utils.helpers import chain
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from pendulum import timezone
import re

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

SOURCE = "aragog"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2023, 10, 3, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"

config_service = ConfigurationService(SOURCE)

CRAWLERS_LIST = config_service.get_config("extracted_tables")
CLEAN_PARTITION_COLS = config_service.get_config("clean_partition_cols")

DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
DATABRICKS_BIETLEJUICE_REPO_PATH = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
CLUSTER_DESCRIPTION = config_service.get_config("cluster_description")
DOC_MD_CHART_URL = config_service.get_config("doc_md_chart_url")

cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")

RAW_SPARK_JOB_FILE = (
    f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/{SOURCE}/load_{SOURCE}_raw.py"
)
BASE_SPARK_JOBS_PATH = f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/base/"

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
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=DOC_MD_CHART_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
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
)

raw_task_groups = {}
for crawler in CRAWLERS_LIST.keys():
    for table in CRAWLERS_LIST[crawler]:
        table_name = f"{crawler}_{table}"
        raw_task_group = task_group.build_raw_task_group_for_single_table(
            source=SOURCE,
            target_database_base_name=SOURCE,
            table_name=table_name,
            extraction_spark_job_file=RAW_SPARK_JOB_FILE,
            raw_spark_job_extra_args=[
                SOURCE,
                table_name,
                crawler,
                table,
            ],
            has_hive_sync=False,
        )
        raw_task_groups[table_name] = raw_task_group

        clean_task_groups = task_group.build_task_group_from_sql_files(
            layer=LayerEnum.CLEAN,
            source_database_base_name=SOURCE,
            target_database_base_name=SOURCE,
            is_incremental=False,
            has_create_external_table_task=False,
            partitions=CLEAN_PARTITION_COLS,
        )

        chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups))
        TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)
        terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))

        # adding data quality tasks
        independent_tasks = DatalakeTaskGroup.independent_tasks(clean_task_groups)

        if independent_tasks:
            terminate_cluster_task.set_upstream(independent_tasks)
