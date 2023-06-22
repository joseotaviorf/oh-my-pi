import os
from datetime import datetime
import re

import pendulum
from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain, cross_downstream

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService

# dag vars
SOURCE = "notify_me"
CONTEXT = SOURCE

DAG_ID = f"bietlejuice.{CONTEXT}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2023, 4, 25, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 3 * * *"

# airflow vars
ENV = os.environ.get("ENVIRONMENT")

CONFIG_SERVICE = ConfigurationService(SOURCE)
default_libraries = CONFIG_SERVICE.get_config("default_libraries")
DATALAKE_BUCKET = CONFIG_SERVICE.get_config("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = CONFIG_SERVICE.get_config("athena_query_results_bucket")
S3_PREFIX = CONFIG_SERVICE.get_config("databricks_bietlejuice_repo_path")
DOC_MD_BASE_URL = CONFIG_SERVICE.get_config("doc_md_chart_url")

# spark and databricks vars
BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/{CONTEXT}"
RAW_LOAD_SPARK_JOB_PATH = f"{RAW_SPARK_JOB_PATH}/load_{SOURCE}_into_datalake.py"

LOGS_OUTPUT_PATH = CONFIG_SERVICE.get_config("spark_jobs_logs_path")
CLUSTER_DESCRIPTION = CONFIG_SERVICE.get_config("databricks_10_4_med_io-memory_cluster")

TABLES = CONFIG_SERVICE.get_config("tables")
PARTITION_COLS = CONFIG_SERVICE.get_config("partition_cols")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

def get_date_param(dag_run, ds, date_param_name):
    date_param = dag_run.conf.get(date_param_name) if dag_run.conf else None
    if date_param and re.match(r"[0-9]{4}\-[0-9]{2}\-[0-9]{2}", date_param):
        return date_param
    return ds

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(CONTEXT).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
    user_defined_macros={"get_date_param": get_date_param},    
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

block_list = CONFIG_SERVICE.get_config("block_list")

for table_name, table_config in TABLES.items():
    if table_name in block_list:
        continue
    else:
        extraction_type = table_config["extraction_type"]
        table_name = table_config.get("clean_table_name", table_name)

        is_incremental = table_config.get("extraction_type") == "incremental"
        partitions = PARTITION_COLS if is_incremental else None

        raw_task_group = task_group.build_raw_task_group_for_single_table(
            source=SOURCE,
            target_database_base_name=CONTEXT,
            table_name=table_name,
            extraction_spark_job_file=RAW_LOAD_SPARK_JOB_PATH,
            raw_spark_job_extra_args=[SOURCE,
                                    table_name,
                                    "{{ get_date_param(dag_run, ds, 'load_start_date') }}",
                                    "{{ get_date_param(dag_run, ds, 'load_end_date') }}",
                                    ],
            has_hive_sync=False,
        )

        chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

        clean_task_group = task_group.build_clean_task_group(
            source_database_base_name=CONTEXT,
            target_database_base_name=CONTEXT,
            table_name=table_name,
            is_incremental=is_incremental,
            has_create_external_table_task=False,
            execution_date="",
            extra_query_template_params={
            "load_start_date": "{{ get_date_param(dag_run, ds, 'load_start_date') }}",
            "load_end_date": "{{ get_date_param(dag_run, ds, 'load_end_date') }}",
            },
        )

        cross_downstream(
            DatalakeTaskGroup.last_tasks(raw_task_group),
            DatalakeTaskGroup.first_tasks(clean_task_group),
        )

        terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
