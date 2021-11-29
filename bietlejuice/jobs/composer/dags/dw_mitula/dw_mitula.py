from datetime import datetime
from pendulum import timezone
import os

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)


DW_SCHEMA = "mitula"
CONTEXT = "mitula"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2018, 1, 1, tzinfo=timezone("America/Sao_Paulo"))
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_9_1_min_general_cluster", deserialize_json=True
)
PARTITION_COLS = ["year", "month", "day"]
DW_QUERY_FILTERS = {"year": "{year}", "month": "{month}", "day": "{day}"}

config_service = ConfigurationService(DAG_NAME)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
dw_bucket = config_service.get_config("dw_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
spectrum_iam_role = config_service.get_config("spectrum_iam_role")
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
default_libraries = config_service.get_config("default_libraries")

ENV = os.environ.get("ENVIRONMENT")
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
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
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=default_libraries,
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
    spark_jobs_path=base_spark_jobs_path,
)

dw_staging_task_group = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW_STAGING,
    is_incremental=True,
    partitions=PARTITION_COLS,
    extra_query_template_params=DW_QUERY_FILTERS,
)

dw_task_group = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW,
    spectrum_iam_role=spectrum_iam_role,
    is_incremental=True,
    partitions=PARTITION_COLS,
    extra_query_template_params=DW_QUERY_FILTERS,
)

chain(create_cluster_task, DWTaskGroup.all_first_tasks(dw_staging_task_group))

TaskFlowHelper.chain_task_groups_via_common_table(dw_staging_task_group, dw_task_group)

chain(DWTaskGroup.all_last_tasks(dw_task_group), terminate_cluster_task)
