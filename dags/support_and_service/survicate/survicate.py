import os
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.services.configuration_service import ConfigurationService

# Pipeline Inputs
SOURCE = "survicate"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2020, 11, 1, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"
CLUSTER_DESCRIPTION = "databricks_10_4_med_general_cluster"

config_service = ConfigurationService(SOURCE)

artifacts_bucket = config_service.get_config("artifacts_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

base_spark_job_path = f"{s3_prefix}/spark_jobs/base/"
raw_spark_job_path = f"{s3_prefix}/spark_jobs/{SOURCE}/load_{SOURCE}_raw.py"

cluster_description = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")

tables = config_service.get_config("tables")
partition_cols = config_service.get_config("partition_cols")
dag_documentation = config_service.get_config("dag_documentation")
inner_dependencies = config_service.get_config("inner_dependencies")

CUSTOM_LIBRARIES = [
    {
        "whl": f"{artifacts_bucket}/survicate-api-client-python/"
        f"quintoandar_survicate_api_client-0.1.0-py2.py3-none-any.whl"
    }
]

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
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries + CUSTOM_LIBRARIES,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=SOURCE,
    spark_jobs_path=base_spark_job_path,
)

raw_task_groups = {}
clean_task_groups = {}

for table_name in tables:
    raw_task_groups[table_name] = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        extraction_spark_job_file=raw_spark_job_path,
        raw_spark_job_extra_args=[
            SOURCE,
            table_name,
            "{{ ds }}",
        ],
        has_hive_sync=False,
    )

    clean_task_groups[table_name] = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        has_create_external_table_task=False,
        table_name=table_name,
        partitions=partition_cols,
        is_incremental=True,
    )

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups))

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=raw_task_groups,
    dag_inner_dependencies=inner_dependencies,
)

create_cluster_task.set_downstream(
    DatalakeTaskGroup.all_first_tasks(task_groups_boundaries_without_inner_dependencies)
    + DatalakeTaskGroup.first_tasks(inner_dependencies_task_groups_boundaries)
)

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(
    DatalakeTaskGroup.all_last_tasks(task_groups_boundaries_without_inner_dependencies)
    + DatalakeTaskGroup.all_last_tasks(clean_task_groups)
    + DatalakeTaskGroup.last_tasks(inner_dependencies_task_groups_boundaries)
)
