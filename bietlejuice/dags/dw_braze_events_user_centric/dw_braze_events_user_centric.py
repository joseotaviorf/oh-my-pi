from datetime import datetime
import pendulum
import os

from airflow.models import DAG
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.services import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

DW_SCHEMA = "braze"
CONTEXT = "braze_events_user_centric"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
CLUSTER_DESCRIPTION = "databricks_10_4_med_memory_cluster"

ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(DAG_NAME)
spectrum_iam_role = config_service.get_config("spectrum_iam_role")
dw_bucket = config_service.get_config("dw_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base"

default_libraries = config_service.get_config("default_libraries")
cluster_description = config_service.get_config(CLUSTER_DESCRIPTION)
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 8, 29, 0, 0, 0, tzinfo=LOCAL_TZ)

INCREMENTAL_LOAD_PARAMETERS = {
    "partitions": ["year", "month", "day"],
    "dw_query_filters": {"year": "{year}", "month": "{month}", "day": "{day}"},
}

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

task_group = DWTaskGroup(
    dag=dag,
    env=ENV,
    dw_bucket=dw_bucket,
    dw_schema=DW_SCHEMA,
    relative_query_path=DAG_NAME,
    spark_jobs_path=SPARK_JOBS_PATH,
)

dw_staging_task_group = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW_STAGING,
    is_incremental=True,
    partitions=INCREMENTAL_LOAD_PARAMETERS["partitions"],
    extra_query_template_params=INCREMENTAL_LOAD_PARAMETERS["dw_query_filters"],
)

dw_task_group = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW,
    spectrum_iam_role=spectrum_iam_role,
    is_incremental=True,
    partitions=INCREMENTAL_LOAD_PARAMETERS["partitions"],
    extra_query_template_params=INCREMENTAL_LOAD_PARAMETERS["dw_query_filters"],
    has_load_to_redshift_task=False,
)

chain(create_cluster_task, DWTaskGroup.all_first_tasks(dw_staging_task_group))

TaskFlowHelper.chain_task_groups_via_common_table(dw_staging_task_group, dw_task_group)

chain(DWTaskGroup.all_last_tasks(dw_task_group), terminate_cluster_task)
