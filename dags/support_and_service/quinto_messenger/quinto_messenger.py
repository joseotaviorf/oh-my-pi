import json
import os
import pendulum
from datetime import datetime

from airflow.models import DAG
from airflow.utils.helpers import chain, cross_downstream
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.services.configuration_service import ConfigurationService


# dag vars
SOURCE = "quinto_messenger"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2020, 7, 27, tzinfo=pendulum.timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"
CLUSTER_DESCRIPTION = "databricks_10_4_med_general_cluster"


config_service = ConfigurationService(dag_name=SOURCE)
datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"
raw_spark_jobs_path = f"{s3_prefix}/spark_jobs/{SOURCE}/load_{SOURCE}_raw.py"

default_libraries = config_service.get_config("default_libraries")
cluster_description = config_service.get_config(CLUSTER_DESCRIPTION)

tables = config_service.get_config("tables")
partition_cols = config_service.get_config("partition_cols")
dag_documentation = config_service.get_config("dag_documentation")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
ENV = os.environ.get("ENVIRONMENT")
DAG_OWNER = DAGOwnerEnum.DATA_SS

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
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
        dag_owner=DAG_OWNER,
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    cluster_configuration=cluster_description,
    libraries=default_libraries,
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

for table_name, table_details in tables.items():
    raw_table_name = table_details.get("raw_table_name", table_name.lower())
    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=raw_table_name,
        extraction_spark_job_file=raw_spark_jobs_path,
        raw_spark_job_extra_args=[
            SOURCE,
            json.dumps(table_details),
            table_name,
            raw_table_name,
            json.dumps(partition_cols),
            "{{ ds }}",
        ],
        has_hive_sync=False
    )

    clean_table_name = table_details.get("clean_table_name", raw_table_name)
    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=clean_table_name,
        partitions=partition_cols if table_details.get("is_incremental") else None,
        is_incremental=True if table_details.get("is_incremental") else False,
    )

    chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

    cross_downstream(
        DatalakeTaskGroup.first_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(raw_task_group))
    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
