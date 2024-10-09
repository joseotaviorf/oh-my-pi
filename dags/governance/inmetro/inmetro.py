import json
import os
from datetime import datetime

import pendulum
from airflow.models import DAG
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

SOURCE = "inmetro"
CONTEXT = SOURCE
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(SOURCE)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)

output_tables = config_service.get_config("output_tables")
partition_cols = config_service.get_config("partition_cols")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

DAG_ID = f"bietlejuice.{CONTEXT}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2021, 1, 20, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 5,13 * * *"

CLUSTER_DESCRIPTION = config_service.get_config(
    "databricks_12_2_min_general_photon_cluster"
)
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.DATA_PLATFORM_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
RAW_SPARK_JOBS_PATH = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/{CONTEXT}/load_{CONTEXT}_raw.py"
)

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
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
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

raw_task_groups = {}
for item in output_tables:

    table_name = item["table_name"]
    bucket_directory = item["bucket_directory"]

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=CONTEXT,
        table_name=table_name,
        target_database_base_name=CONTEXT,
        extraction_spark_job_file=RAW_SPARK_JOBS_PATH,
        raw_spark_job_extra_args=[
            CONTEXT,
            table_name,
            bucket_directory,
            json.dumps(partition_cols),
            "{{ ds }}",
        ],
    )

    raw_task_groups[table_name] = raw_task_group

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
    is_incremental=True,
    partitions=partition_cols,
)

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups))
TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)
terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
