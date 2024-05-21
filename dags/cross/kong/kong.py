import json
import os
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain, cross_downstream

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService


# Pipeline Inputs
SOURCE = "kong"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2023, 4, 3, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 3 * * *"
CLUSTER_DESCRIPTION = "databricks_10_4_max_io-memory_cluster"

config_service = ConfigurationService(dag_name=SOURCE)
datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"
raw_spark_job_path = f"{s3_prefix}/spark_jobs/{SOURCE}/load_{CONTEXT}_raw.py"

default_libraries = config_service.get_config("default_libraries")
cluster_description = config_service.get_config(CLUSTER_DESCRIPTION)

table_name = config_service.get_config("table_name")
partition_cols = config_service.get_config("partition_cols")
dag_documentation = config_service.get_config("dag_documentation")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
ENV = os.environ.get("ENVIRONMENT")
DAG_OWNER = DAGOwnerEnum.DEFAULT_OWNER

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
    athena_query_result_location=athena_query_results_bucket,
)

raw_task_groups = task_group.build_raw_task_group_for_all_tables(
    source=SOURCE,
    target_database_base_name=SOURCE,
    extraction_spark_job_file=raw_spark_job_path,
    raw_spark_job_extra_args=[
        SOURCE,
        table_name,
        json.dumps(partition_cols),
        "{{ ds }}",
    ],
)

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    has_create_external_table_task=False,
    is_incremental=True,
    partitions=partition_cols,
)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_groups))
cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_groups),
    DatalakeTaskGroup.all_first_tasks(clean_task_groups),
)
terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
