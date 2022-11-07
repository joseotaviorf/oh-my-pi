import os
import json
from datetime import datetime
from pendulum import timezone

from airflow.operators.dummy_operator import DummyOperator
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from airflow.utils.helpers import chain

from bietlejuice.base.airflow import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

# ENV setup (forno ou prod)
ENV = os.environ.get("ENVIRONMENT")

# DAG params setup
SOURCE = "emlio"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2021, 9, 20, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "30 0 * * *"

TABLE_NAME = "emlio_logs"

config_service = ConfigurationService(SOURCE)
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
partition_cols = config_service.get_config("partition_cols")
datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")

# s3 paths setup
BASE_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs"
BASE_SPARK_JOBS_PATH = f"{BASE_PATH}/base/"
RAW_SPARK_JOB_PATH = f"{BASE_PATH}/{SOURCE}/"
RAW_SPARK_JOB_FILE = f"{RAW_SPARK_JOB_PATH}load_{SOURCE}_raw.py"


# cluster setup
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_10_4_med_io-memory_cluster", deserialize_json=True
)
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.DATA_PRODUCTS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

doc_md_chart_url = config_service.get_config("doc_md_chart_url")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.MLOPS,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=SOURCE,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)

raw_task_group = task_group.build_raw_task_group_for_all_tables(
    source=SOURCE,
    target_database_base_name=SOURCE,
    extraction_spark_job_file=RAW_SPARK_JOB_FILE,
    raw_spark_job_extra_args=[SOURCE, json.dumps(partition_cols), "{{ ds }}"],
)

load_clean_table_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load-clean-emlio-logs",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": f"{RAW_SPARK_JOB_PATH}load_table_incremental.py",
            "parameters": [
                "{{ ds }}",
                ENV,
                datalake_bucket,
                SOURCE,
                TABLE_NAME,
                json.dumps(partition_cols),
            ],
        }
    },
)

sync_metastore_table_structure_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"sync-hive-metastore-{LayerEnum.CLEAN.value}-{TABLE_NAME}-structure",
    json={
        "spark_python_task": {
            "python_file": f"{BASE_SPARK_JOBS_PATH}/sync_metastore_tables_structure.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--table-name",
                TABLE_NAME,
            ],
        }
    },
)

sync_metastore_table_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"sync-hive-metastore-{LayerEnum.CLEAN.value}-{TABLE_NAME}-partitions",
    json={
        "spark_python_task": {
            "python_file": f"{BASE_SPARK_JOBS_PATH}/sync_metastore_tables_partitions.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--table-name",
                TABLE_NAME,
            ],
        }
    },
)

propagate_table_metadata_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"propagate-table-metadata-{LayerEnum.CLEAN.value}-{TABLE_NAME}",
    json={
        "spark_python_task": {
            "python_file": f"{BASE_SPARK_JOBS_PATH}/propagate_table_metadata.py",
            "parameters": [
                LayerEnum.CLEAN.value,
                MetadataTypeEnum.LINEAGE.value,
                SOURCE,
                TABLE_NAME,
            ],
        }
    },
)

bypass_task = DummyOperator(
    dag=dag,
    task_id=f"propagation-bypass-{LayerEnum.CLEAN.value}-{TABLE_NAME}",
    trigger_rule="all_done",
)

sync_metastore_table_structure_task.set_downstream(sync_metastore_table_partitions_task)

# metadata branch has a bypass to terminate the Dag even if the metadata propagation fails.
propagate_table_metadata_task.set_downstream(bypass_task)

chain(sync_metastore_table_partitions_task, propagate_table_metadata_task)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

chain(
    DatalakeTaskGroup.last_tasks(raw_task_group),
    load_clean_table_task,
    sync_metastore_table_structure_task,
)

chain(sync_metastore_table_partitions_task, terminate_cluster_task)
chain(bypass_task, terminate_cluster_task)