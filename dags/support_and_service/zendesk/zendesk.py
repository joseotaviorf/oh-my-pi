import os
import pendulum
from datetime import datetime

from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain, cross_downstream

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services import ConfigurationService


SOURCE = "zendesk"
CONTEXT = SOURCE
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(SOURCE)

datalake_bucket = config_service.get_config("datalake_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
default_libraries = config_service.get_config("default_libraries")
dag_documentation = config_service.get_config("dag_documentation")
tables = config_service.get_config("tables")

# s3 paths setup
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
raw_spark_job_path = s3_prefix + f"/spark_jobs/{SOURCE}/add_partitions_to_raw_tables.py"
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"

cluster_description = config_service.get_config("custom_cluster")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

# dag vars
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 9, 9, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"
DAG_OWNER = DAGOwnerEnum.DATA_SS

local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time

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
)

file_list = DAGPackagesPathService.list_queries_files_in_composer(
    dag_name=SOURCE, layer=LayerEnum.CLEAN.value
)


for table_name, configs in tables.items():
    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        table_name=table_name,
        target_database_base_name=SOURCE,
        extraction_spark_job_file=s3_prefix + f"/spark_jobs/{SOURCE}/add_data_from_{configs['source']}_to_raw.py",
        raw_spark_job_extra_args=["{{ ds }}", "{{ next_ds }}", table_name],
    )

    clean_task_group = task_group.build_clean_task_group(
        table_name=table_name,
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        is_incremental=configs["is_incremental"],
        partitions=["year", "month", "day"],
    )

    chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

    cross_downstream(
        DatalakeTaskGroup.first_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
