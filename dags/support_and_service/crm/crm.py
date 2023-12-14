import json
import os
from datetime import datetime
from pendulum import timezone

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

# Pipeline inputs
SOURCE = "crm"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2021, 2, 18, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"
CLUSTER_DESCRIPTION = "custom_cluster"

config_service = ConfigurationService(SOURCE)

datalake_bucket = config_service.get_config("datalake_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"
raw_spark_job_path = f"{s3_prefix}/spark_jobs/{SOURCE}/load_{CONTEXT}_raw.py"

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
        "owner": DAGOwnerEnum.DATA_SS,
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
)

for raw_table_name, table_details in tables.items():

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        table_name=raw_table_name,
        target_database_base_name=CONTEXT,
        extraction_spark_job_file=raw_spark_job_path,
        raw_spark_job_extra_args=[
            SOURCE,
            raw_table_name,
            json.dumps(table_details),
            json.dumps(partition_cols),
            "{{ ds }}",
        ],
        has_hive_sync=False
    )

    clean_table_name = table_details.get("clean_table_name", raw_table_name)
    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        has_create_external_table_task=False,
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
