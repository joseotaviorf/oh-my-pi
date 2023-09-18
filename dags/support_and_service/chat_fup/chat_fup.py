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
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum


# dag vars
SOURCE = "chat_fup"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 3 * * *"
DAG_OWNER = DAGOwnerEnum.DATA_SS

# config vars
ENV = os.environ.get("ENVIRONMENT")
config_service = ConfigurationService(SOURCE)
tables = config_service.get_config("tables")
partition_cols = config_service.get_config("partition_cols")

athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

# s3 paths setup
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
raw_spark_job_path = s3_prefix + f"/spark_jobs/{SOURCE}/load_{SOURCE}_raw.py"
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"

# cluster setup
cluster_description = config_service.get_config(
    "databricks_10_4_med_general_photon_cluster"
)
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
default_libraries = config_service.get_config("default_libraries")
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

for raw_table_name, table_info in tables.items():
    raw_task_groups = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=raw_table_name,
        extraction_spark_job_file=raw_spark_job_path,
        raw_spark_job_extra_args=[
            "{{ ds }}",
            SOURCE,
            raw_table_name,
            json.dumps(table_info),
            json.dumps(partition_cols),
        ],
    )

    clean_task_groups = task_group.build_task_group_from_sql_files(
        layer=LayerEnum.CLEAN,
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=raw_table_name,
        is_incremental=True if table_info.get("partitioned") else False,
        partitions=partition_cols if table_info.get("partitioned") else None,
    )

    chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_groups))

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_groups),
        DatalakeTaskGroup.all_first_tasks(clean_task_groups),
    )

    terminate_cluster_task.set_upstream(
        DatalakeTaskGroup.all_last_tasks(clean_task_groups)
    )
