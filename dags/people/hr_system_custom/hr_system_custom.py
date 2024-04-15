import json
import os
import pendulum
from datetime import datetime

from airflow.models import DAG
from airflow.utils.helpers import chain, cross_downstream
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG and Jobs params setup
SOURCE = "hr_system_custom"
CONTEXT = SOURCE

DAG_NAME = CONTEXT
DAG_ID = f"bietlejuice.{SOURCE}"
DAG_OWNER = DAGOwnerEnum.DATA_PEOPLE

MAIN_START_DATE = datetime(
    2020, 10, 1, 0, 0, 0, tzinfo=pendulum.timezone("America/Sao_Paulo")
)
MAIN_SCHEDULE_INTERVAL = "0 3 * * *"

config_service = ConfigurationService(DAG_NAME)

# S3 path setup
datalake_bucket = config_service.get_config("people_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
raw_spark_job_path = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/load_{SOURCE}_raw.py"
)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

cluster_description = config_service.get_config("databricks_12_2_min_people_cluster")
default_libraries = config_service.get_config("default_libraries")

dag_documentation = config_service.get_config("dag_documentation")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.PEOPLE_ANALYTICS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

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
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries,
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
)
table_name = "workers_registration"

raw_task_group = task_group.build_raw_task_group_for_single_table(
    source=SOURCE,
    target_database_base_name=SOURCE,
    table_name=table_name,
    extraction_spark_job_file=raw_spark_job_path,
    has_hive_sync=False,
    raw_spark_job_extra_args=[
        SOURCE,
        table_name
    ],
)

clean_task_group = task_group.build_clean_task_group(
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    has_create_external_table_task=False,
    table_name=table_name,
    has_hive_sync=False,
)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_group),
    DatalakeTaskGroup.first_tasks(clean_task_group),
)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))