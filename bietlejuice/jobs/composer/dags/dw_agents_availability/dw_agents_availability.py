import os
from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 2, 20, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "agents_availability"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")


config_service = ConfigurationService(DAG_NAME)

databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
dw_bucket = config_service.get_config("dw_bucket")
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
spectrum_iam_role = config_service.get_config("spectrum_iam_role")

incremental_load_parameters = config_service.get_config("incremental_load_parameters")
inner_dependencies = config_service.get_config("inner_dependencies")
partition_cols = incremental_load_parameters["partitions"]
dw_query_filters = incremental_load_parameters["dw_query_filters"]

SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base"

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{spark_jobs_logs_path}{DAG_ID}"


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
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

tables = config_service.get_config("tables")

dw_staging_task_group = {}
dw_task_group = {}
for table in tables:
    table_name = table["table_name"]
    dw_schema = table.get("schema")

    task_group = DWTaskGroup(
        dag=dag,
        env=ENV,
        dw_bucket=dw_bucket,
        dw_schema=dw_schema,
        relative_query_path=DAG_NAME,
        spark_jobs_path=SPARK_JOBS_PATH,
    )

    dw_staging_task_group[table_name] = task_group.build_dw_staging_task_group(
        table_name=table_name,
        is_incremental=True,
        partitions=partition_cols,
        extra_query_template_params=dw_query_filters,
    )

    dw_task_group[table_name] = task_group.build_dw_task_group(
        table_name=table_name,
        spectrum_iam_role=spectrum_iam_role,
        is_incremental=True,
        partitions=partition_cols,
        extra_query_template_params=dw_query_filters,
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

chain(DWTaskGroup.all_last_tasks(dw_task_group), terminate_cluster_task)
