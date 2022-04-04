import os
import pendulum
from datetime import datetime

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain
from airflow.operators.python_operator import ShortCircuitOperator
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


def check_valid_run_date(dag_execution_date):
    if datetime.strptime(dag_execution_date, "%Y-%m-%d").day in [3, 12]:
        return True


LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 8, 29, 0, 0, 0, tzinfo=LOCAL_TZ)
ENV = os.environ.get("ENVIRONMENT")

DW_SCHEMA = "payment_snapshot"
CONTEXT = "invoice_entries_snapshot"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

config_service = ConfigurationService(DAG_NAME)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
dw_bucket = config_service.get_config("dw_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
spectrum_iam_role = config_service.get_config("spectrum_iam_role")
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base"
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{spark_jobs_logs_path}{DAG_ID}"

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
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

skip_run_task = ShortCircuitOperator(
    task_id=f"check-day-to-skip-execution",
    python_callable=check_valid_run_date,
    op_kwargs={"dag_execution_date": "{{ds}}"},
)

task_group = DWTaskGroup(
    dag=dag,
    env=ENV,
    dw_bucket=dw_bucket,
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
        spectrum_iam_role=spectrum_iam_role,
        partitions=partitions,
    )

chain(
    skip_run_task,
    create_cluster_task,
    DWTaskGroup.all_first_tasks(dw_staging_task_group),
)
TaskFlowHelper.chain_task_groups_via_common_table(dw_staging_task_group, dw_task_group)
chain(DWTaskGroup.all_last_tasks(dw_task_group), terminate_cluster_task)
