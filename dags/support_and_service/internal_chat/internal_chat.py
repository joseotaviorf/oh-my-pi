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
SOURCE = "internal_chat"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2023, 5, 26, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"

config_service = ConfigurationService(dag_name=SOURCE)
datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"
raw_spark_job_path = f"{s3_prefix}/spark_jobs/{SOURCE}/load_{CONTEXT}_raw.py"

default_libraries = config_service.get_config("default_libraries")
cluster_description = config_service.get_config("custom_cluster")

tables_config = config_service.get_config("tables")
partition_cols = config_service.get_config("partition_cols")
dag_documentation = config_service.get_config("dag_documentation")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
ENV = os.environ.get("ENVIRONMENT")
DAG_OWNER = DAGOwnerEnum.DATA_SS

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

for table, infos in tables_config.items():
    raw_task_groups = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        table_name=infos.get("raw_table_name", table),
        target_database_base_name=SOURCE,
        extraction_spark_job_file=raw_spark_job_path,
        raw_spark_job_extra_args=[
            SOURCE,
            "{{ ds }}",
            infos.get("raw_table_name", table),
            json.dumps(partition_cols),
        ],
    )

    clean_task_groups = task_group.build_task_group_from_sql_files(
        layer=LayerEnum.CLEAN,
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=infos.get("clean_table_name", table),
        is_incremental=True if infos.get("extraction_type") else False,
        partitions=partition_cols,
    )

    chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_groups))
    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_groups),
        DatalakeTaskGroup.all_first_tasks(clean_task_groups),
    )
    terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
