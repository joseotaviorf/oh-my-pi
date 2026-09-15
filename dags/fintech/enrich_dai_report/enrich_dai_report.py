import os
from datetime import datetime

import pendulum
from airflow.models import DAG
from airflow.utils.helpers import chain

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.datasets.dataset_adder import DatasetAdder
from bietlejuice.base.airflow.job_cluster_engine import (
    attach_job_cluster_engine_to_context,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.jiraops.jiraops_callback import JiraOpsCallback
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.dataset_service import DatasetService
from bietlejuice.services.file_service import FileService

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 7, 1, 0, 0, 0, tzinfo=LOCAL_TZ)

SOURCE = "dai_report"
DAG_NAME = f"enrich_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")

jiraops_callback = JiraOpsCallback()

config_service = ConfigurationService(DAG_NAME)
datalake_bucket = config_service.get_config("datalake_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
DAI_CUSTOM_SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{DAG_NAME}/"

_cluster_file_path = DAGPackagesPathService.resolve_artifact_file_path(
    artifact_type="dag_cluster", dag_name=DAG_NAME
)
CLUSTER_ARGS = FileService.get_dict_from_yaml_file(_cluster_file_path)["cluster"]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FINTECH,
        "wait_for_downstream": False,
        "depends_on_past": False,
        "on_failure_callback": jiraops_callback.task_failure_alert,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=DatasetService.get_dag_datasets(DAG_ID),
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
    params=BaseDAG.get_default_trigger_form_params(),
)

dag_execution_context = DagExecutionContext(
    dag=dag,
    environment=ENV,
    bucket=datalake_bucket,
    base_spark_jobs_path=databricks_bietlejuice_repo_path,
    dag_args={},
    workflow_args={},
    cluster_args=CLUSTER_ARGS,
)
attach_job_cluster_engine_to_context(dag_execution_context, config_service)

execute_job_cluster_task = (
    dag_execution_context.job_cluster_engine.create_execute_cluster_task(
        config_service=config_service,
        minimum_cluster_runtime_version=None,
        execute_job_cluster_local_id=None,
    )
)

# Reprocessing guard task to ensure that the DAG does not run multiple times unnecessarily
DatasetAdder.attach_reprocessing_guard(execute_job_cluster_task, dag_execution_context)

terminate_cluster_task = (
    dag_execution_context.job_cluster_engine.create_emr_terminate_cluster_task(
        execute_cluster_task_id=execute_job_cluster_task.task_id,
        terminate_task_local_suffix=None,
    )
)

datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=SPARK_JOBS_PATH,
    job_cluster_engine=dag_execution_context.job_cluster_engine,
)

enrich_task_groups = datalake_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.ENRICH,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
)

query_export_xlsx = config_service.get_config("query_export_xlsx")
out_path = config_service.get_config("out_path")
load_data_into_s3 = dag_execution_context.job_cluster_engine.create_spark_python_task(
    spark_job_path=f"{DAI_CUSTOM_SPARK_JOB_PATH}load_data_into_xlsx_s3.py",
    task_id=f"load-{SOURCE}-in-s3",
    job_parameters=[
        ENV,
        SOURCE,
        query_export_xlsx,
        out_path,
        "{{ data_interval_start | ds}}",
    ],
    execution_timeout_hours=1,
)

chain(
    execute_job_cluster_task,
    DatalakeTaskGroup.all_first_tasks(enrich_task_groups),
)
chain(
    DatalakeTaskGroup.all_last_tasks(enrich_task_groups),
    load_data_into_s3,
    terminate_cluster_task,
)
