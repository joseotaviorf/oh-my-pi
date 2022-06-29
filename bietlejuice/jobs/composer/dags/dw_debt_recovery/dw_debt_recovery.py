from datetime import datetime
from pendulum import timezone
import os

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

ENV = os.environ.get("ENVIRONMENT")
MAIN_START_DATE = datetime(2020, 8, 6, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))

DW_SCHEMA = "debt_recovery"
CONTEXT = "debt_recovery"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

config_service = ConfigurationService(DAG_NAME)
SPECTRUM_IAM_ROLE = config_service.get_config("spectrum_iam_role")
DW_BUCKET = config_service.get_config("dw_bucket")
DOC_MD_CHART_URL = config_service.get_config("doc_md_chart_url")
DATABRICKS_BIETLEJUICE_REPO_PATH = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)

SPARK_JOBS_LOGS_PATH = config_service.get_config("spark_jobs_logs_path")
BASE_SPARK_JOBS_PATH = f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/base"

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_dw_tracksale_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{SPARK_JOBS_LOGS_PATH}{DAG_ID}"

inner_dependencies = config_service.get_config("inner_dependencies")


dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_BEDROCK,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_CHART_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DWTaskGroup(
    dag=dag,
    env=ENV,
    dw_bucket=DW_BUCKET,
    dw_schema=DW_SCHEMA,
    relative_query_path=DAG_NAME,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
)

dw_staging_task_group = {}
dw_task_group = {}
tables = task_group._get_table_names_from_sql_files(layer=LayerEnum.DW)

for table in tables:
    partitions = ["year", "month", "day"]

    dw_staging_task_group[table] = task_group.build_dw_staging_task_group(
        table_name=table, is_incremental=True, partitions=partitions
    )

    dw_task_group[table] = task_group.build_dw_task_group(
        table_name=table,
        is_incremental=True,
        spectrum_iam_role=SPECTRUM_IAM_ROLE,
        partitions=partitions,
        has_load_to_redshift_task=True,
    )

dw_task_group_boundaries = {}
for table in dw_task_group:
    initial_tasks = DWTaskGroup.first_tasks(dw_staging_task_group[table])
    final_tasks = DWTaskGroup.last_tasks(dw_task_group[table])
    dw_task_group_boundaries[table] = DWTaskGroup.format_tasks_boundaries(
        initial_tasks=initial_tasks, final_tasks=final_tasks
    )

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=dw_task_group_boundaries,
    dag_inner_dependencies=inner_dependencies,
)

chain(
    create_cluster_task,
    DWTaskGroup.all_first_tasks(task_groups_boundaries_without_inner_dependencies)
    + DWTaskGroup.first_tasks(inner_dependencies_task_groups_boundaries),
)

TaskFlowHelper.chain_task_groups_via_common_table(dw_staging_task_group, dw_task_group)

chain(
    DWTaskGroup.all_last_tasks(task_groups_boundaries_without_inner_dependencies)
    + DWTaskGroup.last_tasks(inner_dependencies_task_groups_boundaries),
    terminate_cluster_task,
)
