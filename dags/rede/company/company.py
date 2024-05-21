import os
import pendulum
from datetime import datetime

from airflow.utils.helpers import chain, cross_downstream
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers.task_flow_helper import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

SOURCE = "company"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
ENV = os.environ.get("ENVIRONMENT")
MAIN_START_DATE = datetime(2021, 8, 10, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 21 * * *"

config_service = ConfigurationService(SOURCE)
default_libraries = config_service.get_config("default_libraries")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/" "load_company_raw.py"
)

CLUSTER_DESCRIPTION = config_service.get_config("databricks_10_4_med_general_cluster")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_REDE,
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
    datalake_bucket=datalake_bucket,
    relative_query_path=CONTEXT,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)

tables = config_service.get_config("tables")
inner_dependencies = config_service.get_config("inner_dependencies")
clean_task_groups = {}

for table in tables:
    table_name = table["table_name"]
    clean_table_name = table.get("clean_table_name", table_name)
    raw_extraction_type = table.get("raw_extraction_type", "incremental")
    clean_extraction_type = table.get("clean_extraction_type", "incremental")
    partition_cols = (
        None
        if raw_extraction_type == "full"
        else config_service.get_config("partition_cols")
    )
    parameters = [SOURCE, table_name]

    extended_parameters = [
        table["date_filter_column"],
        "{{ ds }}",
        raw_extraction_type,
        table.get("unixtime_measure", None),
    ]

    extended_parameters = list(filter(None, extended_parameters))
    parameters.extend(extended_parameters)

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        table_name=table_name,
        target_database_base_name=CONTEXT,
        extraction_spark_job_file=RAW_SPARK_JOB_PATH,
        raw_spark_job_extra_args=parameters,
    )

    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        table_name=clean_table_name,
        is_incremental=clean_extraction_type == "incremental",
        partitions=partition_cols if clean_extraction_type == "incremental" else None,
    )

    clean_task_groups[table_name] = clean_task_group

    chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))


    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=clean_task_groups,
    dag_inner_dependencies=inner_dependencies,
)
