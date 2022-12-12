import os
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

# Pipeline inputs
DW_SCHEMA = "inspections"
CONTEXT = "inspections"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2021, 2, 7, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None
CLUSTER_DESCRIPTION = "databricks_10_4_med_io-general_cluster"

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

incremental_tables = config_service.get_config("incremental_tables")
partitions_cols = config_service.get_config("partitions_cols")
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
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=DAG_NAME,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=dag_documentation,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        dag_owner=DAG_OWNER,
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

dw_task_group = DWTaskGroup(
    dag=dag,
    env=ENV,
    dw_bucket=dw_bucket,
    dw_schema=DW_SCHEMA,
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
)

dw_staging_task_group = {}
dw_task_groups = {}

tables = dw_task_group._get_table_names_from_sql_files(layer=LayerEnum.DW)

for table_name in tables:
    is_incremental = table_name in incremental_tables
    partitions = partitions_cols if is_incremental else None

    dw_staging_task_group[table_name] = dw_task_group.build_dw_staging_task_group(
        table_name=table_name, is_incremental=is_incremental, partitions=partitions
    )

    dw_task_groups[table_name] = dw_task_group.build_dw_task_group(
        table_name=table_name,
        has_load_to_redshift_task=False,
        is_incremental=is_incremental,
        spectrum_iam_role=spectrum_iam_role,
        partitions=partitions,
    )

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

chain(create_cluster_task, DWTaskGroup.all_first_tasks(dw_staging_task_group))

TaskFlowHelper.chain_task_groups_via_common_table(dw_staging_task_group, dw_task_groups)

chain(DWTaskGroup.all_last_tasks(dw_task_groups), terminate_cluster_task)
