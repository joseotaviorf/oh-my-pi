from datetime import datetime
import pendulum
import os

from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers.task_flow_helper import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.services.configuration_service import ConfigurationService

from airflow.utils.helpers import chain

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 7, 1, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "ebdb_user"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(DAG_NAME)

DATABRICKS_BIETLEJUICE_REPO_PATH = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
BASE_SPARK_JOBS_PATH = f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/base/"

datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_result_location = config_service.get_config("athena_query_results_bucket")
user_merge_table_name = config_service.get_config("user_merge_table_name")
default_libraries = config_service.get_config("default_libraries")

doc_md_chart_url = config_service.get_config("doc_md_chart_url")

s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"

cluster_description = config_service.get_config("custom_cluster")

user_merge_file = (
    f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/{DAG_NAME}/user_merge.py"
)

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

CUSTOM_LIBRARIES = [{"maven": {"coordinates": "graphframes:graphframes:0.8.1-spark3.0-s_2.12"}}]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries + CUSTOM_LIBRARIES,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=spark_jobs_path,
    athena_query_result_location=athena_query_result_location,
)

partition_cols = config_service.get_config("partition_cols")
inner_dependencies = config_service.get_config("inner_dependencies")


enrich_task_groups = datalake_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.ENRICH,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
    partitions=partition_cols,
)

user_merge_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=DatalakeTaskGroup.LOAD_TASK_PREFIX,
        layer=LayerEnum.ENRICH,
        schema=CONTEXT,
        table_name=user_merge_table_name,
    ),
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": user_merge_file,
            "parameters": [
                ENV,
                datalake_bucket,
                DAG_NAME,
                user_merge_table_name,
                CONTEXT,
            ],
        }
    },
)

sync_metadata_user_merge_task = datalake_task_group._build_metadata_sync_task(
    source=CONTEXT,
    sync_mode=datalake_task_group.SINGLE_TABLE,
    layer=LayerEnum.ENRICH.value,
    database_name=CONTEXT,
    table_name=user_merge_table_name,
    metadata_file_type=MetadataTypeEnum.LINEAGE.value,
)

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = datalake_task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=enrich_task_groups,
    dag_inner_dependencies=inner_dependencies,
)

chain(
    create_cluster_task,
    datalake_task_group.all_first_tasks(
        task_groups_boundaries_without_inner_dependencies
    )
    + datalake_task_group.first_tasks(inner_dependencies_task_groups_boundaries),
)

chain(
    create_cluster_task,
    user_merge_task,
    sync_metadata_user_merge_task,
)

chain(
    sync_metadata_user_merge_task,
    terminate_cluster_task,
)

chain(
    datalake_task_group.all_last_tasks(
        task_groups_boundaries_without_inner_dependencies
    )
    + datalake_task_group.last_tasks(inner_dependencies_task_groups_boundaries),
    terminate_cluster_task,
)
