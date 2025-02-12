import os
from datetime import datetime

import pendulum
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain, cross_downstream

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.opsgenie.opsgenie_callback import OpsgenieCallback

from dags import DAG_PACKAGES_ROOT


SOURCE = "crawlers"
CONTEXT = f"listings"
ORIGIN = f"loft"
DAG_NAME = f"{CONTEXT}.{ORIGIN}"
SOURCE_WITH_CONTEXT = f"{SOURCE}_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
DAG_NAME_PARTIAL = f"{SOURCE}/{CONTEXT}"
CONFIG_NAME = "crawlers_listings"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
ENV = os.environ.get("ENVIRONMENT")
MAIN_START_DATE = datetime(2021, 6, 10, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 2 * * 1"

config_service = ConfigurationService(
    dag_name=DAG_NAME_PARTIAL, intermediate_path=CONTEXT
)
default_libraries = config_service.get_config("default_libraries")

loft_configs = config_service.get_config("loft")
origin = loft_configs["origin"]

athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{DAG_NAME_PARTIAL}"

CLUSTER_DESCRIPTION = config_service.get_config("databricks_12_2_med_general_cluster")

CLUSTER_DESCRIPTION["data_security_mode"] = "SINGLE_USER"
CLUSTER_DESCRIPTION["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
CLUSTER_DESCRIPTION["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = "quintoandar_{{ var.value.environment }}"
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
opsgenie_callback = OpsgenieCallback()
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
        "wait_for_downstream": False,
        "depends_on_past": False,
        "on_failure_callback": opsgenie_callback.task_failure_alert,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(
        dag_name=ORIGIN,
        template_path=f"{DAG_PACKAGES_ROOT}/cross/{SOURCE}/{CONTEXT}",
    ).format(chart_url=doc_md_chart_url, dag_id=DAG_ID),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(databricks_conn_id="databricks_new", dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(databricks_conn_id="databricks_new", dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=SOURCE,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)

partition_cols = config_service.get_config("partition_cols")


raw_spark_job_path = f"{RAW_SPARK_JOB_PATH}/load_crawlers_listings_into_datalake.py"
parameters = [SOURCE, CONTEXT, origin, origin, "{{ds}}"]


raw_task_group = task_group.build_raw_task_group_for_single_table(
    source=SOURCE_WITH_CONTEXT,
    table_name=origin,
    target_database_base_name=SOURCE_WITH_CONTEXT,
    extraction_spark_job_file=raw_spark_job_path,
    raw_spark_job_extra_args=parameters,
)

clean_task_group = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE_WITH_CONTEXT,
    target_database_base_name=SOURCE_WITH_CONTEXT,
    tree_path=f"{CONTEXT}/{ORIGIN}/",
    partitions=partition_cols,
)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_group),
    DatalakeTaskGroup.all_first_tasks(clean_task_group),
)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_group))
