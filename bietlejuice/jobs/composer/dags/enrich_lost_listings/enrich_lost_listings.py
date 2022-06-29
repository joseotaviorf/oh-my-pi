import os
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
from bietlejuice.jobs.composer.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)
from bietlejuice.jobs.composer.base.databricks import (
    DatabricksGroupNameEnum,
    ClusterPermissionEnum,
)

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# Pipeline inputs
SOURCE = "lost_listings"
CONTEXT = "marketing_segmentations"
DAG_NAME = f"enrich_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2019, 1, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None
CLUSTER_DESCRIPTION = "databricks_10_4_med_memory_cluster"

config_service = ConfigurationService(DAG_NAME)
PARTITION_COLS = config_service.get_config("partition_cols")
TABLE_NAME = config_service.get_config("table_name")
SLUGGED_TABLE_NAME = config_service.get_config("slugged_table_name")
CUSTOM_LIBRARIES = config_service.get_config("custom_libraries")

athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")

ENRICH_SPARK_JOB_PATH = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/{DAG_NAME}/load_{SOURCE}_enrich.py"
)

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
ENV = os.environ.get("ENVIRONMENT")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    catchup=True,
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries + CUSTOM_LIBRARIES,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

load_table_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"load-{LayerEnum.ENRICH.value}-{SLUGGED_TABLE_NAME}",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": ENRICH_SPARK_JOB_PATH,
            "parameters": [ENV, datalake_bucket, SOURCE, CONTEXT, "{{ ds }}"],
        }
    },
)

create_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"create-{LayerEnum.ENRICH.value}-{SLUGGED_TABLE_NAME}-external-table",
    json={
        "spark_python_task": {
            "python_file": f"{base_spark_jobs_path}/create_external_table.py",
            "parameters": [
                ENV,
                datalake_bucket,
                athena_query_results_bucket,
                LayerEnum.ENRICH.value,
                CONTEXT,
                TABLE_NAME,
                str(PARTITION_COLS),
                True,
            ],
        }
    },
)

sync_metastore_table_structure_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"sync-hive-metastore-{LayerEnum.ENRICH.value}-{SLUGGED_TABLE_NAME}-structure",
    json={
        "spark_python_task": {
            "python_file": f"{base_spark_jobs_path}/sync_metastore_tables_structure.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.ENRICH.value,
                CONTEXT,
                "--table-name",
                TABLE_NAME,
            ],
        }
    },
)

sync_metastore_table_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"sync-hive-metastore-{LayerEnum.ENRICH.value}-{SLUGGED_TABLE_NAME}-partitions",
    json={
        "spark_python_task": {
            "python_file": f"{base_spark_jobs_path}/sync_metastore_tables_partitions.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.ENRICH.value,
                CONTEXT,
                "--table-name",
                TABLE_NAME,
            ],
        }
    },
)

propagate_table_metadata_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"propagate-table-metadata-{LayerEnum.ENRICH.value}-{SLUGGED_TABLE_NAME}",
    json={
        "spark_python_task": {
            "python_file": f"{base_spark_jobs_path}/propagate_table_metadata.py",
            "parameters": [
                LayerEnum.ENRICH.value,
                MetadataTypeEnum.LINEAGE.value,
                CONTEXT,
                TABLE_NAME,
            ],
        }
    },
)

chain(
    create_cluster_task,
    load_table_task,
    sync_metastore_table_structure_task,
    sync_metastore_table_partitions_task,
    propagate_table_metadata_task,
    terminate_cluster_task,
)
chain(load_table_task, create_external_table_task, terminate_cluster_task)
