import os
from datetime import datetime

import pendulum
from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 12, 12, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "cozy_metrics"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

config_service = ConfigurationService(DAG_NAME)

DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
DATABRICKS_BIETLEJUICE_REPO_PATH = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
CLUSTER_DESCRIPTION = config_service.get_config("cluster_description")
SPARK_JOBS_LOGS_PATH = config_service.get_config("spark_jobs_logs_path")
DOC_MD_CHART_URL = config_service.get_config("doc_md_chart_url")
BASE_SPARK_JOBS_PATH = f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/base/"

cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

ENV = os.environ.get("ENVIRONMENT")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_CHART_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    relative_query_path=DAG_NAME,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)

enrich_task_groups = datalake_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.ENRICH,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
    is_incremental=False,
    has_create_external_table_task=False,
)

create_cluster_task.set_downstream(
    DatalakeTaskGroup.all_first_tasks(enrich_task_groups)
)
terminate_cluster_task.set_upstream(
    DatalakeTaskGroup.all_last_tasks(enrich_task_groups)
)
