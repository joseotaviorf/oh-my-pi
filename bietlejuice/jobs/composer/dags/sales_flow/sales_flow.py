import os
from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain, cross_downstream

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

# dag vars
SOURCE = "sales_flow"
CONTEXT = SOURCE

DAG_ID = f"bietlejuice.{CONTEXT}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2021, 3, 2, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 4 * * *"

# airflow vars
ENV = os.environ.get("ENVIRONMENT")

CONFIG_SERVICE = ConfigurationService(SOURCE)
DATALAKE_BUCKET = CONFIG_SERVICE.get_config("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = CONFIG_SERVICE.get_config("athena_query_results_bucket")
S3_PREFIX = CONFIG_SERVICE.get_config("databricks_bietlejuice_repo_path")
DOC_MD_BASE_URL = CONFIG_SERVICE.get_config("doc_md_chart_url")

# spark and databricks vars
BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/{CONTEXT}"
RAW_LOAD_SPARK_JOB_PATH = f"{RAW_SPARK_JOB_PATH}/load_sales_flow_into_datalake.py"

LOGS_OUTPUT_PATH = CONFIG_SERVICE.get_config("spark_jobs_logs_path")
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{LOGS_OUTPUT_PATH}{CONTEXT}"

TABLES = CONFIG_SERVICE.get_config("tables")
PARTITION_COLS = CONFIG_SERVICE.get_config("partition_cols")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_SALE,
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
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
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
    extraction_spark_job_file=RAW_LOAD_SPARK_JOB_PATH,
    raw_spark_job_extra_args=[SOURCE, "{{ds}}"],
)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

for table_name, table_config in TABLES.items():
    extraction_type = table_config["extraction_type"]
    clean_table_name = table_config.get("clean_table_name", table_name)

    is_incremental = table_config.get("extraction_type") == "incremental"
    partitions = PARTITION_COLS if is_incremental else None

    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        table_name=clean_table_name,
        is_incremental=is_incremental,
        partitions=partitions,
    )

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
