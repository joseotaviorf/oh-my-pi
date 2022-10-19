from datetime import datetime
import os
import pendulum

from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain

from bietlejuice.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService


LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
ENV = os.environ.get("ENVIRONMENT")
MAIN_START_DATE = datetime(2020, 12, 2, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "call"
DW_SCHEMA = "call"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

config_service = ConfigurationService(dag_name=DAG_NAME)

# airflow vars
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
dw_bucket = config_service.get_config("dw_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
spectrum_iam_role = config_service.get_config("spectrum_iam_role")

# spark and databricks vars
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base"

cluster_description = config_service.get_config("databricks_10_4_med_general_cluster")

default_libraries = config_service.get_config("default_libraries")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_SS,
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

dw_task_group = DWTaskGroup(
    dag=dag,
    env=ENV,
    dw_bucket=dw_bucket,
    dw_schema=DW_SCHEMA,
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
)

dw_staging_task_group = dw_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW_STAGING
)

dw_task_group = dw_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW, spectrum_iam_role=spectrum_iam_role
)

chain(create_cluster_task, DWTaskGroup.all_first_tasks(dw_staging_task_group))
TaskFlowHelper.chain_task_groups_via_common_table(dw_staging_task_group, dw_task_group)
chain(DWTaskGroup.all_last_tasks(dw_task_group), terminate_cluster_task)
