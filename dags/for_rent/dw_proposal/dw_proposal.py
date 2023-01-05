from datetime import datetime
import pendulum
import os

from airflow.models import DAG
from airflow.utils.helpers import chain, cross_downstream
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.task_groups.dw_task_group import DWTaskGroup
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 2, 20, 0, 0, 0, tzinfo=LOCAL_TZ)

DW_SCHEMA = "public"
CONTEXT = "proposal"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
CLUSTER_DESCRIPTION = "databricks_10_4_min_general_cluster"

config_service = ConfigurationService(DAG_NAME)
dw_bucket = config_service.get_config("dw_bucket")
spectrum_iam_role = config_service.get_config("spectrum_iam_role")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
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
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
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
    cluster_configuration=cluster_configuration,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

tables = config_service.get_config("tables")
for table_name, table_config in tables.items():
    dw_schema = table_config["dw_schema"]

    task_group = DWTaskGroup(
        dag=dag,
        env=ENV,
        dw_bucket=dw_bucket,
        dw_schema=dw_schema,
        relative_query_path=DAG_NAME,
        spark_jobs_path=base_spark_jobs_path,
    )

    dw_staging_task_group = task_group.build_dw_staging_task_group(
        table_name=table_name
    )

    dw_task_group = task_group.build_dw_task_group(
        table_name=table_name, spectrum_iam_role=spectrum_iam_role
    )

    chain(create_cluster_task, DWTaskGroup.first_tasks(dw_staging_task_group))
    cross_downstream(
        DWTaskGroup.last_tasks(dw_staging_task_group),
        DWTaskGroup.first_tasks(dw_task_group),
    )
    chain(DWTaskGroup.last_tasks(dw_task_group), terminate_cluster_task)
