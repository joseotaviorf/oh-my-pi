from datetime import datetime
import json
import os
import pendulum

from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain, cross_downstream

from bietlejuice.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService

# Pipeline Inputs
SOURCE = "saruman"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"
CLUSTER_DESCRIPTION = "databricks_10_4_med_general_cluster"

# Dag Inputs
ENV = os.environ.get("ENVIRONMENT")
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2022, 11, 20, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 3 * * *"

config_service = ConfigurationService(dag_name=SOURCE)

# Airflow Inputs
datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")

# Spark and Databricks Inputs
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"
raw_spark_job_path = f"{s3_prefix}/spark_jobs/{SOURCE}/load_{CONTEXT}_into_datalake.py"

cluster_description = config_service.get_config(CLUSTER_DESCRIPTION)

default_libraries = config_service.get_config("default_libraries")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

tables = config_service.get_config("tables")
partition_cols = config_service.get_config("partition_cols")
max_records_per_file = config_service.get_config("max_records_per_file")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_SS,
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
    spark_jobs_path=base_spark_jobs_path,
    athena_query_result_location=athena_query_results_bucket,
)

for raw_table_name, table_details in tables.items():
    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=raw_table_name,
        extraction_spark_job_file=raw_spark_job_path,
        raw_spark_job_extra_args=[
            SOURCE,
            json.dumps(table_details),
            raw_table_name,
            max_records_per_file,
            json.dumps(partition_cols),
            "{{ ds }}",
        ],
    )

    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        has_create_external_table_task=False,
        table_name=table_details["clean_table_name"],
        partitions=partition_cols if table_details.get("is_incremental") else None,
        is_incremental=True if table_details.get("is_incremental") else False,
    )

    chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
