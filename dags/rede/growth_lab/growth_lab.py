import os
import pendulum
from datetime import datetime

from airflow.utils.helpers import chain, cross_downstream
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

SOURCE = "growth_lab"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
ENV = os.environ.get("ENVIRONMENT")
MAIN_START_DATE = datetime(2021, 8, 10, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 2 * * *"
PARTITION_COLS = ["year", "month", "day"]

config_service = ConfigurationService(SOURCE)
default_libraries = config_service.get_config("default_libraries")
custom_libraries = config_service.get_config("custom_libraries")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/" "load_growth_lab_raw.py"
)

CLUSTER_DESCRIPTION = config_service.get_config("databricks_12_2_med_general_cluster")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

DAG_OWNER = DAGOwnerEnum.DATA_REDE
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
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries + custom_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=CONTEXT,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
)

tables = config_service.get_config("tables")

for table in tables:
    table_name = table["table_name"]
    gcp_bucket_name = table["gcp_bucket_name"]
    prefix_template = table["prefix_template"]

    parameters = [
        SOURCE,
        table_name,
        "{{ ds }}",
        gcp_bucket_name,
        prefix_template,
    ]

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        table_name=table_name,
        target_database_base_name=CONTEXT,
        extraction_spark_job_file=RAW_SPARK_JOB_PATH,
        raw_spark_job_extra_args=parameters,
    )

    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        table_name=table_name,
        is_incremental=True,
        partitions=PARTITION_COLS,
    )

    chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
