import os
from datetime import datetime
from dateutil.relativedelta import relativedelta
import math

import pendulum
from airflow.utils.helpers import chain
from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.airflow.helpers.task_flow_helper import TaskFlowHelper
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum


def get_date_from_previous_quarter(execution_date):
    return datetime.strptime(execution_date, "%Y-%m-%d") - relativedelta(months=3)


def get_previous_quarter(execution_date):
    return math.ceil((get_date_from_previous_quarter(execution_date).month) / 3)


LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 7, 1, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "brand_tracking"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

config_service = ConfigurationService(DAG_NAME)
ATHENA_QUERY_RESULT_BUCKET = config_service.get_config("athena_query_results_bucket")
DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
DATABRICKS_BIETLEJUICE_REPO_PATH = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
SPARK_JOBS_LOGS_PATH = config_service.get_config("spark_jobs_logs_path")
BASE_SPARK_JOBS_PATH = f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/base/"
DOC_MD_CHART_URL = config_service.get_config("doc_md_chart_url")

PARTITION_COLS = config_service.get_config("partition_cols")

# cluster setup
CLUSTER_DESCRIPTION = "databricks_10_4_min_general_cluster"
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

ENV = os.environ.get("ENVIRONMENT")

INNER_DEPENDENCIES = {"brandtracking_lean": ["brandtracking_full"]}

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_CHART_URL, dag_id=DAG_ID
    ),
    user_defined_macros={
        "get_date_from_previous_quarter": get_date_from_previous_quarter,  # Macro can also be a function
        "get_previous_quarter": get_previous_quarter,
    },
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    relative_query_path=DAG_NAME,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_BUCKET,
)

enrich_task_groups = datalake_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.ENRICH,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
    is_incremental=True,
    partitions=PARTITION_COLS,
    cluster_config_params={"udfs": ["SF_ALPHANUMERIC_SNAKE_CASE"]},
    extra_query_template_params={
        "year_previous_quarter": "{{ get_date_from_previous_quarter(ds).year }}",
        "previous_quarter": "{{ get_previous_quarter(ds) }}",
    },
)

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = datalake_task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=enrich_task_groups,
    dag_inner_dependencies=INNER_DEPENDENCIES,
)

chain(
    create_cluster_task,
    datalake_task_group.all_first_tasks(
        task_groups_boundaries_without_inner_dependencies
    )
    + datalake_task_group.first_tasks(inner_dependencies_task_groups_boundaries),
)

chain(
    datalake_task_group.all_last_tasks(
        task_groups_boundaries_without_inner_dependencies
    )
    + datalake_task_group.last_tasks(inner_dependencies_task_groups_boundaries),
    terminate_cluster_task,
)
