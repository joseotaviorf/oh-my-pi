import os
from datetime import datetime, timedelta

import pendulum
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks.cluster_permission_enum import ClusterPermissionEnum
from bietlejuice.base.databricks.databricks_group_name_enum import (
    DatabricksGroupNameEnum,
)
from bietlejuice.services.configuration_service import ConfigurationService

VESPUCIO_PACKAGE_NAME = "vespucio"

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2021, 8, 24, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 7 * * 1"

DAG_NAME = "zordominium_vespucio_plugin"
DAG_ID = f"bietlejuice.{DAG_NAME}"

ENV = os.environ.get("ENVIRONMENT")
EXECUTION_HOURS_TIMEOUT = 2.0

config_service = ConfigurationService(DAG_NAME)
artifacts_bucket = config_service.get_config("artifacts_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

VESPUCIO_PACKAGE_VERSION = config_service.get_config("vespucio_pipeline_version")
VESPUCIO_WHEEL_FILE = f"{VESPUCIO_PACKAGE_NAME}-{VESPUCIO_PACKAGE_VERSION}-py3-none-any.whl"

CLUSTER_DESCRIPTION = config_service.get_config("databricks_13_3_med_general_cluster")
CLUSTER_DESCRIPTION["data_security_mode"] = "SINGLE_USER"
CLUSTER_DESCRIPTION["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
CLUSTER_DESCRIPTION["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = "quintoandar_{{ var.value.environment }}"
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
LIBRARIES = [{"whl": f"{artifacts_bucket}/vespucio/{VESPUCIO_WHEEL_FILE}"}]
DAG_DOCUMENTATION = config_service.get_config("dag_documentation")
DAG_OWNER = DAGOwnerEnum.DATA_GROWTH

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=DAG_NAME,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=DAG_DOCUMENTATION,
        dag_owner=DAG_OWNER,
    ),
)

execute_job_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    databricks_conn_id="databricks_new",
    dag=dag,
    task_id="execute-job-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=LIBRARIES,
)

def create_task(entry_point: str, parameters: str, task_id: str = None):
    return QuintoAndarDatabricksSubmitRunOperator(
        databricks_conn_id="databricks_new",
        dag=dag,
        task_id=(task_id or entry_point).replace("_", "-"),
        json={
            "python_wheel_task": {
                "package_name": VESPUCIO_PACKAGE_NAME,
                "entry_point": entry_point,
                "parameters": parameters,
            }
        },
        execution_timeout=timedelta(hours=EXECUTION_HOURS_TIMEOUT),
    )

plugin_task = create_task(
        entry_point="plugins_zordominium",
        parameters=None,
        task_id="zordominium"
    )

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)


execute_job_cluster_task >> plugin_task >> terminate_cluster_task
