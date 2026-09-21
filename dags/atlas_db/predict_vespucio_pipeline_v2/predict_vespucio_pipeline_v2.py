import os
from datetime import datetime

import pendulum
from airflow.models import DAG
from airflow.operators.dummy_operator import DummyOperator

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.job_cluster_engine import (
    attach_emr_terminate_cluster_work_prerequisites,
    attach_job_cluster_engine_to_context,
    get_job_cluster_completion_sink,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.notification.gchat_callback import GchatCallback
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.file_service import FileService
from dags.atlas_db.vespucio_pipeline_table_names import Tables

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2026, 9, 17, 0, 0, 0, tzinfo=LOCAL_TZ)

DAG_NAME = "predict_vespucio_pipeline_v2"
DAG_ID = f"bietlejuice.{DAG_NAME}"

ENV = os.environ.get("ENVIRONMENT")
MAIN_SCHEDULE_INTERVAL = None if ENV == "forno" else "0 17 * * *"
EXECUTION_HOURS_TIMEOUT = 3

config_service = ConfigurationService(DAG_NAME)
datalake_bucket = config_service.get_config("datalake_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
output_location = config_service.get_config("vespucio_output_path")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)

_cluster_file_path = DAGPackagesPathService.resolve_artifact_file_path(
    artifact_type="dag_cluster", dag_name=DAG_NAME
)
CLUSTER_ARGS = FileService.get_dict_from_yaml_file(_cluster_file_path)["cluster"]
custom_configurations = CLUSTER_ARGS.setdefault("custom_configurations", {})
# setdefault keeps PYSPARK_* / PYTHONPATH from the cluster YAML (Python 3.11).
custom_configurations.setdefault("spark_env_vars", {})["OUTPUT_LOCATION"] = (
    output_location
)
custom_configurations.setdefault("spark_conf", {})["spark.metrics.namespace"] = (
    "data_products.predict_vespucio_pipeline_v2"
)

DAG_DOCUMENTATION = config_service.get_config("dag_documentation")
DAG_OWNER = DAGOwnerEnum.DATA_ATLAS_DB
webhook_vespucio_pipeline_v2 = config_service.get_config("webhook_vespucio_pipeline_v2")
callback_by_task_failure = config_service.get_config("callback_by_task_failure")
callback_by_task_success = config_service.get_config("callback_by_task_success")

gchat_callback = GchatCallback(webhook_url_variable=webhook_vespucio_pipeline_v2)

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
        "on_success_callback": (
            gchat_callback.task_success_alert if callback_by_task_success else None
        ),
        "on_failure_callback": (
            gchat_callback.task_failure_alert if callback_by_task_failure else None
        ),
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    catchup=False,
    max_active_runs=1,
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=DAG_NAME,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=DAG_DOCUMENTATION,
        dag_owner=DAG_OWNER,
    ),
    params=BaseDAG.get_default_trigger_form_params(),
    on_success_callback=(
        gchat_callback.dag_success_alert if not callback_by_task_success else None
    ),
    on_failure_callback=(
        gchat_callback.dag_failure_alert if not callback_by_task_failure else None
    ),
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

typology_built_area_predictor_task = dag_execution_context.job_cluster_engine.create_spark_python_task(
    spark_job_path=(
        f"{databricks_bietlejuice_repo_path}/spark_jobs/{DAG_NAME}/"
        "typology_built_area_predictor.py"
    ),
    task_id="typology-built-area-predictor",
    job_parameters=[
        f"--input_groups={Tables.groups_step_v2}",
        f"--input_match_anchors={Tables.match_anchors_v2}",
        f"--input_pins={Tables.pins_step_v2}",
        f"--input_source_itbi_houses_v2={Tables.source_itbi_houses_v2}",
        f"--input_source_idactum_houses_v2={Tables.source_idactum_houses_v2}",
        f"--output_typology_built_area_predictor={Tables.typology_built_area_predictor}",
    ],
    execution_timeout_hours=EXECUTION_HOURS_TIMEOUT,
)

job_cluster_finished_task = DummyOperator(task_id="job-cluster-finished", dag=dag)
cluster_completion_sink = get_job_cluster_completion_sink(
    dag_execution_context,
    execute_job_cluster_task,
    job_cluster_finished_task,
)

execute_job_cluster_task >> typology_built_area_predictor_task
typology_built_area_predictor_task >> cluster_completion_sink
attach_emr_terminate_cluster_work_prerequisites(
    dag_execution_context,
    cluster_completion_sink,
    execute_job_cluster_task=execute_job_cluster_task,
    job_cluster_finished_task=job_cluster_finished_task,
)
