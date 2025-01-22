from datetime import datetime
import json
import pendulum
import os

from airflow.models import DAG
from airflow.utils.helpers import chain, cross_downstream
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

SOURCE = "nexxera"
CONTEXT = SOURCE
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(SOURCE)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 11, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "30 7 * * *"

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
CUSTOM_SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/"

CLUSTER_DESCRIPTION = config_service.get_config("custom_cluster")

CLUSTER_DESCRIPTION["data_security_mode"] = "SINGLE_USER"
CLUSTER_DESCRIPTION["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
CLUSTER_DESCRIPTION["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = "quintoandar_{{ var.value.environment }}"
LIBRARIES_DESCRIPTION = config_service.get_config("default_libraries")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

CONSUMER_EXTRA_ARGS = config_service.get_config("consumer_extra_args")



dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FINTECH,
        "wait_for_downstream": False,
        "depends_on_past": False,
     },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=LIBRARIES_DESCRIPTION,
)


terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(databricks_conn_id="databricks_new", dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(databricks_conn_id="databricks_new", dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=CONTEXT,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)

tables = config_service.get_config("tables")
inner_dependencies = config_service.get_config("inner_dependencies")

raw_task_groups = {}
clean_task_groups = {}

for table in tables:
    table_name = table["table_name"]
    has_raw = table.get("has_raw", True)

    if has_raw == True:
        SOURCE_ROOT_PATH = table["source_root_path"]
        format = table["format"]
        col_names = table.get("col_names")
        raw_task_groups[table_name] = task_group.build_raw_task_group_for_single_table(
            source=SOURCE,
            table_name=table_name,
            target_database_base_name=SOURCE,
            extraction_spark_job_file=f"{CUSTOM_SPARK_JOB_PATH}/load_csv_into_datalake.py",
            raw_spark_job_extra_args=[
                SOURCE,
                SOURCE_ROOT_PATH,
                "{{ ds }}",
                table_name,
                json.dumps(CONSUMER_EXTRA_ARGS),
                format,
                json.dumps(col_names)
            ],
        )

    partition_columns = config_service.get_config("partition_cols")

    clean_task_groups[table_name] = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        is_incremental=True,
        partitions=partition_columns,
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
