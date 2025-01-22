from datetime import datetime
import pendulum
import os

from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain, cross_downstream

from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup

from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

SOURCE = "vans"
CONTEXT = SOURCE

DAG_NAME = CONTEXT
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
config_service = ConfigurationService(DAG_NAME)

# S3 path setup
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
raw_spark_job_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/load_{SOURCE}_into_datalake.py"
artifacts_bucket = config_service.get_config("artifacts_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")

cluster_description = config_service.get_config("databricks_12_2_med_memory_cluster")


cluster_description["data_security_mode"] = "SINGLE_USER"
cluster_description["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
cluster_description["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = "quintoandar_{{ var.value.environment }}"
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

DEFAULT_LIBRARIES = config_service.get_config("default_libraries")
CUSTOM_LIBRARIES = [
    {"jar": f"{artifacts_bucket}/mysql-connector-java/mysql-connector-java-5.1.47.jar"}
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

# dag params
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 10, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 8 * * *"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FINTECH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=LIBRARIES_DESCRIPTION,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(databricks_conn_id="databricks_new", dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(databricks_conn_id="databricks_new", dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=CONTEXT,
    spark_jobs_path=base_spark_jobs_path,
    athena_query_result_location=athena_query_results_bucket,
    execution_timeout_hours=3,
)

raw_task_group = task_group.build_raw_task_group_for_all_tables(
    source=CONTEXT,
    target_database_base_name=CONTEXT,
    extraction_spark_job_file=raw_spark_job_path,
)

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_group),
    DatalakeTaskGroup.all_first_tasks(clean_task_groups),
)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
