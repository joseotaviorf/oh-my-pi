from datetime import datetime
from pendulum import timezone
import os

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)


DW_SCHEMA = "braze"
CONTEXT = "braze_events_user_dispatch"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2020, 11, 1, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_9_1_med_general_cluster", deserialize_json=True
)

FULL_TABLE_NAMES = ["dim_campaign", "dim_canvas"]
FULL_PARTITIONS = ["user_type"]

INCREMENTAL_TABLE_NAMES = ["fact_campaign_user_dispatch", "fact_canvas_user_dispatch"]
INCREMENTAL_QUERY_FILTERS = {"year": "{year}", "month": "{month}", "day": "{day}"}
INCREMENTAL_PARTITIONS = ["year", "month", "day"]

config_service = ConfigurationService(DAG_NAME)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
dw_bucket = config_service.get_config("dw_bucket")
spectrum_iam_role = config_service.get_config("spectrum_iam_role")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
default_libraries = config_service.get_config("default_libraries")

ENV = os.environ.get("ENVIRONMENT")
BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
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
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
)

for incremental_table_name in INCREMENTAL_TABLE_NAMES:
    dw_task_group_incremental = task_group.build_dw_task_group(
        table_name=incremental_table_name,
        partitions=INCREMENTAL_PARTITIONS,
        spectrum_iam_role=spectrum_iam_role,
        is_incremental=True,
        extra_query_template_params=INCREMENTAL_QUERY_FILTERS,
    )
    chain(create_cluster_task, DWTaskGroup.first_tasks(dw_task_group_incremental))
    chain(DWTaskGroup.last_tasks(dw_task_group_incremental), terminate_cluster_task)

for full_table_name in FULL_TABLE_NAMES:
    dw_task_group_full = task_group.build_dw_task_group(
        table_name=full_table_name,
        partitions=FULL_PARTITIONS,
        spectrum_iam_role=spectrum_iam_role,
        is_incremental=False,
    )
    chain(create_cluster_task, DWTaskGroup.first_tasks(dw_task_group_full))
    chain(DWTaskGroup.last_tasks(dw_task_group_full), terminate_cluster_task)
