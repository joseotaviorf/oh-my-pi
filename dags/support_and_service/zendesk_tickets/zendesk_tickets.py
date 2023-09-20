import os
import pendulum
from datetime import datetime

from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.services import ConfigurationService


SOURCE = "zendesk_tickets"
CONTEXT = SOURCE
config_service = ConfigurationService(SOURCE)
ENV = os.environ.get("ENVIRONMENT")

athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
default_libraries = config_service.get_config("default_libraries")
tables = config_service.get_config("tables")
inner_dependencies = config_service.get_config("inner_dependencies")
dag_documentation = config_service.get_config("dag_documentation")

# s3 paths setup
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
raw_spark_job_path = s3_prefix + f"/spark_jobs/{SOURCE}/add_partitions_to_raw_tables.py"
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"

cluster_description = config_service.get_config("custom_cluster")

# Testing Granulate script for Spark job auto optimization
# TODO Remove after PoV complete (reach out to either Ribs, Mario or Edu for any clarification and cleansing)

cluster_description['init_scripts'].append({"s3": {"destination": "s3://artifacts.s3.data.quintoandar.com.br/granulate/sagent_installer_Databricks.sh", "region": ""}})


DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

# dag vars
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 9, 9, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"
DAG_OWNER = DAGOwnerEnum.DATA_SS

local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time

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

raw_task_groups = {}
clean_task_groups = {}
for table_name, configs in tables.items():
    partitions = configs.get("partition_cols")
    is_incremental = configs.get("is_incremental")
    has_create_external_table = configs.get("has_create_external_table")
    no_raw = configs.get("no_raw")

    if not no_raw:
        raw_task_groups[table_name] = task_group.build_raw_task_group_for_single_table(
            source=SOURCE,
            table_name=table_name,
            target_database_base_name=SOURCE,
            extraction_spark_job_file=raw_spark_job_path,
            raw_spark_job_extra_args=["{{ ds }}", "{{ next_ds }}", table_name],
        )

    clean_task_groups[table_name] = task_group.build_clean_task_group(
        table_name=table_name,
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        is_incremental=is_incremental,
        has_create_external_table_task=has_create_external_table,
        partitions=partitions,
    )

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups))

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=clean_task_groups,
    dag_inner_dependencies=inner_dependencies,
)

chain(
    create_cluster_task,
    DatalakeTaskGroup.all_first_tasks(task_groups_boundaries_without_inner_dependencies)
    + DatalakeTaskGroup.first_tasks(inner_dependencies_task_groups_boundaries),
)

chain(
    DatalakeTaskGroup.all_last_tasks(task_groups_boundaries_without_inner_dependencies)
    + DatalakeTaskGroup.last_tasks(inner_dependencies_task_groups_boundaries),
    terminate_cluster_task,
)
TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)
