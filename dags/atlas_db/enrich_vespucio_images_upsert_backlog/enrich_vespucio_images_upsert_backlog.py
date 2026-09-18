from datetime import datetime, timedelta
from typing import List

import pendulum
from airflow.models import DAG
from airflow.models.param import Param
from airflow.operators.python_operator import BranchPythonOperator
from airflow.utils.trigger_rule import TriggerRule
from databricks_plugin import (
    QuintoAndarDatabricksCheckJobTaskOperator,
    QuintoAndarDatabricksExecuteJobClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.databricks.cluster_permission_enum import ClusterPermissionEnum
from bietlejuice.base.databricks.databricks_group_name_enum import (
    DatabricksGroupNameEnum,
)
from bietlejuice.base.notification.gchat_callback import GchatCallback
from bietlejuice.services.configuration_service import ConfigurationService
from dags.atlas_db.vespucio_pipeline_table_names import Tables

VESPUCIO_PACKAGE_NAME = "vespucio"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2026, 9, 16, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "vespucio_images_upsert_backlog"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

EXECUTION_HOURS_TIMEOUT = 3.0

REBUILD_BACKLOG_QUEUE_PARAM = "rebuild_backlog_queue"
BUILD_STEP_TASK_ID = "core_v2_images_upsert_backlog_build_step"
DRAIN_STEP_TASK_ID = "core_v2_images_upsert_backlog_step"

config_service = ConfigurationService(DAG_NAME)
artifacts_bucket = config_service.get_config("artifacts_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
output_location = config_service.get_config("vespucio_output_path")
kodak_photo_sns_arn = config_service.get_config("kodak_photo_sns_arn")
images_upsert_backlog_dry_run_preview_table = config_service.get_config(
    "images_upsert_backlog_dry_run_preview_table"
)

VESPUCIO_PACKAGE_VERSION = config_service.get_config("vespucio_pipeline_version")
VESPUCIO_WHEEL_FILE = (
    f"{VESPUCIO_PACKAGE_NAME}-{VESPUCIO_PACKAGE_VERSION}-py3-none-any.whl"
)

CLUSTER_DESCRIPTION = config_service.get_config("custom_cluster")
CLUSTER_DESCRIPTION["spark_conf"].update(
    {"spark.metrics.namespace": "data_products.enrich_vespucio_images_upsert_backlog"}
)
CLUSTER_DESCRIPTION["spark_env_vars"]["OUTPUT_LOCATION"] = output_location
CLUSTER_DESCRIPTION["data_security_mode"] = "SINGLE_USER"
CLUSTER_DESCRIPTION["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
CLUSTER_DESCRIPTION["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = (
    "quintoandar_{{ var.value.environment }}"
)
CLUSTER_DESCRIPTION["driver_node_type_id"] = "r5a.4xlarge"
CLUSTER_DESCRIPTION["node_type_id"] = "c5a.4xlarge"
CLUSTER_DESCRIPTION["num_workers"] = 6

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    },
    {
        "group_name": DatabricksGroupNameEnum.SOFTWARE_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    },
]

LIBRARIES = [
    {"whl": f"{artifacts_bucket}/vespucio/{VESPUCIO_WHEEL_FILE}"},
]

DAG_DOCUMENTATION = config_service.get_config("dag_documentation")
DAG_OWNER = DAGOwnerEnum.DATA_ATLAS_DB
webhook_vespucio_pipeline_v2 = config_service.get_config("webhook_vespucio_pipeline_v2")
callback_by_task_failure = config_service.get_config("callback_by_task_failure")
callback_by_task_success = config_service.get_config("callback_by_task_success")

gchat_callback = GchatCallback(webhook_url_variable=webhook_vespucio_pipeline_v2)

BUILD_STEP_PARAMETERS = [
    f"--input_image_normalized={Tables.image_normalization_step_v2}",
    f"--input_general_normalized={Tables.general_normalization_step_v2}",
    f"--input_kodak_photo={Tables.kodak_photo}",
    f"--input_source_kodak_atlas_images={Tables.source_kodak_atlas_images_v2}",
    f"--input_kodak_photo_invalid_source={Tables.kodak_photo_invalid_source}",
    f"--output_images_upsert_backlog_queue={Tables.images_upsert_backlog_queue}",
    f"--output_images_upsert_backlog_progress={Tables.images_upsert_backlog_progress}",
    f"--output_images_upsert_backlog_failed={Tables.images_upsert_backlog_failed}",
]

DRAIN_STEP_PARAMETERS = [
    f"--input_images_upsert_backlog_queue={Tables.images_upsert_backlog_queue}",
    f"--input_images_upsert_backlog_progress={Tables.images_upsert_backlog_progress}",
    f"--output_images_upsert_backlog_progress={Tables.images_upsert_backlog_progress}",
    f"--input_images_upsert_backlog_failed={Tables.images_upsert_backlog_failed}",
    f"--output_images_upsert_backlog_failed={Tables.images_upsert_backlog_failed}",
    f"--configcat_sdk_key_path={APIEnum.VESPUCIO_CONFIGCAT_SDK_KEY_PATH}",
]
if kodak_photo_sns_arn:
    DRAIN_STEP_PARAMETERS.extend(
        [
            f"--kodak_photo_sns_arn={kodak_photo_sns_arn}",
            "--kodak_photo_sns_region=us-east-1",
        ]
    )
else:
    DRAIN_STEP_PARAMETERS.append(
        f"--dry_run_preview_table={images_upsert_backlog_dry_run_preview_table}"
    )


def _wheel_task_json(entry_point: str, parameters: List[str]) -> dict:
    return {
        "python_wheel_task": {
            "package_name": VESPUCIO_PACKAGE_NAME,
            "entry_point": entry_point,
            "parameters": parameters,
        }
    }


def _job_cluster_key(dag_id: str, run_id: str) -> str:
    return (
        f"{dag_id}_{run_id}".replace(".", "-")
        .replace(":", "")
        .replace("+", "_")
        .replace("_triggered", "")
    )


def job_tasks(rebuild: bool, dag_id: str, run_id: str) -> list:
    """Build the Databricks job task list submitted by execute-job-cluster.

    Must stay in sync with choose-monitor-branch: when rebuild is false the job
    contains only the drain task (never an empty list — [] would fall back to
    auto-generation from the Airflow graph and re-introduce the build step).
    """
    cluster_key = _job_cluster_key(dag_id, run_id)
    timeout_seconds = int(EXECUTION_HOURS_TIMEOUT * 3600)
    drain_task = {
        "task_key": DRAIN_STEP_TASK_ID,
        "job_cluster_key": cluster_key,
        "libraries": LIBRARIES,
        "timeout_seconds": timeout_seconds,
        **_wheel_task_json("core_v2_images_upsert_backlog_step", DRAIN_STEP_PARAMETERS),
    }
    if not rebuild:
        return [drain_task]

    build_task = {
        "task_key": BUILD_STEP_TASK_ID,
        "job_cluster_key": cluster_key,
        "libraries": LIBRARIES,
        "timeout_seconds": timeout_seconds,
        **_wheel_task_json(
            "core_v2_images_upsert_backlog_build_step", BUILD_STEP_PARAMETERS
        ),
    }
    drain_task["depends_on"] = [{"task_key": BUILD_STEP_TASK_ID}]
    return [build_task, drain_task]


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
    schedule_interval=None,
    catchup=False,
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=DAG_NAME,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=DAG_DOCUMENTATION,
        dag_owner=DAG_OWNER,
    ),
    params={
        **BaseDAG.get_default_trigger_form_params(),
        REBUILD_BACKLOG_QUEUE_PARAM: Param(
            default=False,
            type="boolean",
            description_md=(
                "When **true**, runs `core_v2_images_upsert_backlog_build_step` before "
                "draining. The build is a one-time cold-start job: rebuilding resets "
                "drain progress and must not be enabled on routine manual triggers. "
                "Leave **false** (default) to drain the existing backlog queue only."
            ),
        ),
    },
    render_template_as_native_obj=True,
    user_defined_macros={"job_tasks": job_tasks},
    on_success_callback=(
        gchat_callback.dag_success_alert if not callback_by_task_success else None
    ),
    on_failure_callback=(
        gchat_callback.dag_failure_alert if not callback_by_task_failure else None
    ),
)

execute_job_cluster_task = QuintoAndarDatabricksExecuteJobClusterOperator(
    databricks_conn_id="databricks_new",
    dag=dag,
    task_id="execute-job-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=LIBRARIES,
    tasks=(
        "{{ job_tasks("
        "dag_run.conf.get('rebuild_backlog_queue', params.rebuild_backlog_queue), "
        "dag.dag_id, run_id) }}"
    ),
)


def create_task(entry_point: str, parameters: List[str], task_id: str = None):
    return QuintoAndarDatabricksCheckJobTaskOperator(
        databricks_conn_id="databricks_new",
        dag=dag,
        task_id=(task_id or entry_point).replace("-", "-"),
        json={
            "python_wheel_task": {
                "package_name": VESPUCIO_PACKAGE_NAME,
                "entry_point": entry_point,
                "parameters": parameters,
            }
        },
        execution_timeout=timedelta(hours=EXECUTION_HOURS_TIMEOUT),
    )


def _should_rebuild_backlog_queue(context: dict) -> bool:
    params = context.get("params") or {}
    dag_run = context.get("dag_run")
    conf = (dag_run.conf or {}) if dag_run else {}
    return bool(
        conf.get(
            REBUILD_BACKLOG_QUEUE_PARAM, params.get(REBUILD_BACKLOG_QUEUE_PARAM, False)
        )
    )


def choose_monitor_branch(**context) -> str:
    if _should_rebuild_backlog_queue(context):
        return BUILD_STEP_TASK_ID
    return DRAIN_STEP_TASK_ID


choose_monitor_branch_task = BranchPythonOperator(
    task_id="choose-monitor-branch",
    python_callable=choose_monitor_branch,
    provide_context=True,
    dag=dag,
)

backlog_build_step_task = create_task(
    entry_point="core_v2_images_upsert_backlog_build_step",
    parameters=BUILD_STEP_PARAMETERS,
    task_id=BUILD_STEP_TASK_ID,
)

backlog_drain_step_task = create_task(
    entry_point="core_v2_images_upsert_backlog_step",
    parameters=DRAIN_STEP_PARAMETERS,
    task_id=DRAIN_STEP_TASK_ID,
)
backlog_drain_step_task.trigger_rule = TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS

execute_job_cluster_task >> choose_monitor_branch_task
choose_monitor_branch_task >> backlog_build_step_task >> backlog_drain_step_task
choose_monitor_branch_task >> backlog_drain_step_task
