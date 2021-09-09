import os
import pendulum
from datetime import datetime

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
from bietlejuice.jobs.composer.services import ConfigurationService

DW_SCHEMA = "janus"
CONTEXT = "lead"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"


configs_service = ConfigurationService(DAG_NAME)
dw_bucket = configs_service.get_config("dw_bucket")
spectrum_iam_role = configs_service.get_config("spectrum_iam_role")
doc_md_chart_url = configs_service.get_config("doc_md_chart_url")
databricks_bietlejuice_repo_path = configs_service.get_config(
    "databricks_bietlejuice_repo_path"
)
spark_jobs_logs_path = configs_service.get_config("spark_jobs_logs_path")

env = os.environ.get("ENVIRONMENT")

spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base"
logs_output_path = f"{spark_jobs_logs_path}{DAG_ID}"
cluster_description = Variable.get("databricks_memory_optimized_cluster", deserialize_json=True)
cluster_description["cluster_log_conf"]["s3"]["destination"] = logs_output_path

local_tz = pendulum.timezone("America/Sao_Paulo")
main_start_date = datetime(2021, 8, 2, 0, 0, 0, tzinfo=local_tz)
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=main_start_date,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=cluster_description
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

dw_task_group = DWTaskGroup(
    dag=dag,
    env=env,
    dw_bucket=dw_bucket,
    dw_schema=DW_SCHEMA,
    relative_query_path=DAG_NAME,
    spark_jobs_path=spark_jobs_path,
)

dw_staging_task_group = dw_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW_STAGING, has_ods_migration_test=True
)

dw_task_group = dw_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW, spectrum_iam_role=spectrum_iam_role
)

chain(create_cluster_task, DWTaskGroup.all_first_tasks(dw_staging_task_group))
TaskFlowHelper.chain_task_groups_via_common_table(dw_staging_task_group, dw_task_group)
chain(DWTaskGroup.all_last_tasks(dw_task_group), terminate_cluster_task)
