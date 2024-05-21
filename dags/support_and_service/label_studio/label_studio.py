from datetime import datetime
import os
import pendulum

from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import cross_downstream

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService

SOURCE = "label_studio"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"

# dag vars
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2022, 3, 30, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 3 * * *"
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(dag_name=SOURCE)

# airflow vars
datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

# spark and databricks vars
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"
raw_spark_job_path = f"{s3_prefix}/spark_jobs/{SOURCE}/load_label_studio_raw.py"

cluster_description = config_service.get_config("databricks_10_4_min_general_cluster")

default_libraries = config_service.get_config("default_libraries")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
DAG_OWNER = DAGOwnerEnum.DATA_SS

table_name = config_service.get_config("table_name")
data_schema = config_service.get_config("schema")
dag_documentation = config_service.get_config("dag_documentation")

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
        dag_name=SOURCE,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=dag_documentation,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        dag_owner=DAG_OWNER,
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=CONTEXT,
    spark_jobs_path=base_spark_jobs_path,
    athena_query_result_location=athena_query_results_bucket,
)

raw_task_group = task_group.build_raw_task_group_for_single_table(
    source=SOURCE,
    target_database_base_name=SOURCE,
    table_name=table_name,
    extraction_spark_job_file=raw_spark_job_path,
    raw_spark_job_extra_args=[SOURCE, table_name, data_schema, "{{ ds }}"],
    has_hive_sync=False
)

clean_task_group = task_group.build_clean_task_group(
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    table_name=table_name,
)

create_cluster_task.set_downstream(DatalakeTaskGroup.first_tasks(raw_task_group))

cross_downstream(
    DatalakeTaskGroup.first_tasks(raw_task_group),
    DatalakeTaskGroup.first_tasks(clean_task_group),
)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(raw_task_group))
terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
