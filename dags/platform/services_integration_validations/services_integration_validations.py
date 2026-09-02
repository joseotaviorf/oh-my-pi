import os
from datetime import datetime

import pendulum
from airflow.models import DAG

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.job_cluster_engine import (
    attach_job_cluster_engine_to_context,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.jiraops.jiraops_callback import JiraOpsCallback
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.file_service import FileService

DAG_NAME = "services_integration_validations"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(
    2021, 1, 20, 0, 0, 0, tzinfo=pendulum.timezone("America/Sao_Paulo")
)
MAIN_SCHEDULE_INTERVAL = "0 13,16,18,20 * * *"

ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(DAG_NAME)
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/{DAG_NAME}"

jiraops_callback = JiraOpsCallback()
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_LIFE_CYCLE,
        "wait_for_downstream": False,
        "depends_on_past": False,
        "on_failure_callback": jiraops_callback.task_failure_alert,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME),
)

# Cluster shape lives in services_integration_validations_cluster.yml.
_cluster_file_path = DAGPackagesPathService.resolve_artifact_file_path(
    artifact_type="dag_cluster", dag_name=DAG_NAME
)
CLUSTER_ARGS = FileService.get_dict_from_yaml_file(_cluster_file_path)["cluster"]

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

run_validations_suites = (
    dag_execution_context.job_cluster_engine.create_spark_python_task(
        spark_job_path=f"{base_spark_jobs_path}/run_validation_suites.py",
        task_id="run-validations-suites",
        job_parameters=[],
        execution_timeout_hours=1,
    )
)
run_validations_suites.retries = 0

terminate_cluster_task = (
    dag_execution_context.job_cluster_engine.create_emr_terminate_cluster_task(
        execute_cluster_task_id=execute_job_cluster_task.task_id,
        terminate_task_local_suffix=None,
    )
)

execute_job_cluster_task >> run_validations_suites >> terminate_cluster_task
