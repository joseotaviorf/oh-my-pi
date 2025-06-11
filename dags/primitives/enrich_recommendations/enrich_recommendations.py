import os
import re
from datetime import datetime

import pendulum
from airflow.models import DAG
from airflow.utils.helpers import chain
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks.cluster_permission_enum import ClusterPermissionEnum
from bietlejuice.base.databricks.databricks_group_name_enum import (
    DatabricksGroupNameEnum,
)
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.airflow.helpers.task_flow_helper import TaskFlowHelper
from bietlejuice.base.opsgenie.opsgenie_callback import OpsgenieCallback


LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2021, 8, 24, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "recommendations"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(DAG_NAME)
athena_query_result_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

CLUSTER_DESCRIPTION = config_service.get_config("custom_cluster")


CLUSTER_DESCRIPTION["data_security_mode"] = "SINGLE_USER"
CLUSTER_DESCRIPTION["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
CLUSTER_DESCRIPTION["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = "quintoandar_{{ var.value.environment }}"
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.DATA_PRODUCTS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
DEFAULT_LIBRARIES = config_service.get_config("default_libraries")


def get_date_param(dag_run, execution_date, date_param_name):
    """
    Custom Airflow macro for handling dates for incremental execution.

    If the date parameter is not available as input for the DAG run,
    fallback to the current execution date
    """
    date_param = dag_run.conf.get(date_param_name) if dag_run.conf else None
    if date_param and re.match(r"[0-9]{4}\-[0-9]{2}\-[0-9]{2}", date_param):
        return date_param
    return execution_date


def get_optional_conf(dag_run, attribute, default):
    """
    Airflow macro for retrieving optional configurations
    """
    if dag_run.conf:
        return dag_run.conf.get(attribute, default)
    return default

opsgenie_callback = OpsgenieCallback()
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_PRIMITIVES,
        "wait_for_downstream": False,
        "depends_on_past": False,
        "on_failure_callback": opsgenie_callback.task_failure_alert,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
    user_defined_macros={
        "get_date_param": get_date_param,
        "get_optional_conf": get_optional_conf,
    },
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=DEFAULT_LIBRARIES,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(databricks_conn_id="databricks_new", dag=dag, task_id="terminate-cluster"
)

datalake_task_group = DatalakeTaskGroup(databricks_conn_id="databricks_new", dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
    athena_query_result_location=athena_query_result_bucket,
)

enrich_task_groups = {}
tables = config_service.get_config("tables")
inner_dependencies = config_service.get_config("inner_dependencies")

for table, configs in tables.items():
    is_incremental = configs.get("is_incremental")
    partition_cols = configs.get("partition_cols")

    enrich_task_groups[table] = datalake_task_group.build_enrich_task_group(
        table_name=table,
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        is_incremental=is_incremental,
        partitions=partition_cols,
        # The following are incremental processing configurations
        #
        # If no explicit start/end dates exists, falls back to the current date
        #
        # All incremental queries will load data between (start_date - days_past) and end_date.
        # The days_past variable is currently set to 15 days by default as we have metrics
        # that are calculated with 14 days delay.
        extra_query_template_params={
            "start_date": "{{ get_date_param(dag_run, data_interval_start | ds, 'start_date') }}",
            "end_date": "{{ get_date_param(dag_run, data_interval_start | ds, 'end_date') }}",
            "days_past": "{{ get_optional_conf(dag_run, 'days_past', 15) }}",
        },
    )


(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = datalake_task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=enrich_task_groups,
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
