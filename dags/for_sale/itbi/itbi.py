import os

from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from airflow.utils.helpers import chain, cross_downstream
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.services.configuration_service import ConfigurationService


SOURCE = "itbi"

CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"
ENV = os.environ.get("ENVIRONMENT")
MAIN_START_DATE = datetime(2020, 12, 21, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 11 15,30 * *"

config_service = ConfigurationService(SOURCE)

athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
clean_partition_cols = config_service.get_config("clean_partition_cols")
cluster_description = config_service.get_config("databricks_12_2_med_memory_cluster")
custom_libraries = config_service.get_config("custom_libraries")
dag_documentation = config_service.get_config("dag_documentation")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
datalake_bucket = config_service.get_config("datalake_bucket")
default_libraries = config_service.get_config("default_libraries")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
tables = config_service.get_config("tables")

base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_SALE,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=SOURCE,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=dag_documentation,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        dag_owner=DAGOwnerEnum.DATA_FOR_SALE,
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    libraries=default_libraries + custom_libraries,
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

for table_name, table_config in tables.items():
    raw_spark_job_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/{CONTEXT}/load_{table_name}_raw.py"

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=CONTEXT,
        table_name=table_name,
        extraction_spark_job_file=raw_spark_job_path,
        raw_spark_job_extra_args=[CONTEXT, "{{ ds }}"],
    )

    is_incremental = table_config.get("is_incremental")
    partitions = clean_partition_cols if is_incremental else None

    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        table_name=table_name,
        is_incremental=is_incremental,
        partitions=partitions,
    )

    chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
