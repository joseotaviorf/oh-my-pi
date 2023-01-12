import os
import pendulum
from datetime import datetime

from airflow.models import DAG
from airflow.utils.helpers import cross_downstream
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

SOURCE = "property_tax"
CONTEXT = SOURCE

# dag vars
DAG_ID = f"bietlejuice.{CONTEXT}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 7, 27, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 3 * * *"

config_service = ConfigurationService(SOURCE)

ENV = os.environ.get("ENVIRONMENT")
datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_result_location = config_service.get_config("athena_query_results_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
doc_md_base_url = config_service.get_config("doc_md_chart_url")
default_libraries = config_service.get_config("default_libraries")

# spark and databricks vars
BASE_SPARK_JOBS_PATH = f"{s3_prefix}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{s3_prefix}/spark_jobs/{CONTEXT}/load_{{extraction_type}}_{CONTEXT}_raw.py"

cluster_description = config_service.get_config("databricks_10_4_med_general_cluster")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(CONTEXT).format(
        chart_url=doc_md_base_url, dag_id=DAG_ID
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

tables = config_service.get_config("tables")
partition_columns = config_service.get_config("partition_cols")

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=CONTEXT,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_result_location,
)

for table in tables:
    table_name = table["table_name"]
    extraction_type = table["extraction_type"]
    is_incremental = extraction_type == "incremental"

    parameters = [SOURCE, table_name]
    if is_incremental:
        parameters.append(table["date_filter_column"])
        parameters.append("{{ ds }}")
        parameters.append(table["read_from_sql_file"])

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=CONTEXT,
        table_name=table_name,
        extraction_spark_job_file=RAW_SPARK_JOB_PATH.format(
            extraction_type=extraction_type
        ),
        raw_spark_job_extra_args=parameters,
    )

    partitions = partition_columns if is_incremental else None
    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        is_incremental=is_incremental,
        partitions=partitions,
        has_create_external_table_task=False
    )

    create_cluster_task.set_downstream(DatalakeTaskGroup.first_tasks(raw_task_group))

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
