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

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# Pipeline inputs
SOURCE = "lost_listings"
CONTEXT = "marketing_segmentations"
DAG_NAME = f"enrich_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2019, 1, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None
CLUSTER_DESCRIPTION = "databricks_10_4_med_general_photon_cluster"

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
    catchup=False,
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
    task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=DatalakeTaskGroup.LOAD_TASK_PREFIX,
        layer=LayerEnum.ENRICH,
        schema=CONTEXT,
        table_name=TABLE_NAME,
    ),
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": ENRICH_SPARK_JOB_PATH,
            "parameters": [ENV, datalake_bucket, SOURCE, CONTEXT, "{{ ds }}"],
        }
    },
)

datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
)

sync_metadata_task = datalake_task_group._build_metadata_sync_task(
    source=CONTEXT,
    sync_mode=datalake_task_group.SINGLE_TABLE,
    layer=LayerEnum.ENRICH.value,
    database_name=CONTEXT,
    table_name=TABLE_NAME,
    metadata_file_type=MetadataTypeEnum.LINEAGE.value,
)

chain(
    create_cluster_task,
    load_table_task,
    sync_metadata_task,
    terminate_cluster_task,
)
