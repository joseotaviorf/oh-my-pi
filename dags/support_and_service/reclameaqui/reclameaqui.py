from datetime import datetime
import os
import pendulum

from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain, cross_downstream
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG and Jobs params setup
SOURCE = "reclameaqui"
CONTEXT = SOURCE
DAG_NAME = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(
    2022, 4, 26, 0, 0, 0, tzinfo=pendulum.timezone("America/Sao_Paulo")
)
MAIN_SCHEDULE_INTERVAL = "0 2 * * *"
DAG_OWNER = DAGOwnerEnum.DATA_SS

config_service = ConfigurationService(DAG_NAME)
tickets_endpoint_config = config_service.get_config("tickets")
partition_cols = tickets_endpoint_config.get("partition_cols")
dag_documentation = config_service.get_config("dag_documentation")

# s3 paths setup
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
artifacts_default_bucket = config_service.get_config("artifacts_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
raw_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/load_incremental_tickets_data_into_datalake_raw.py"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

# cluster setup
cluster_description = config_service.get_config("databricks_10_4_min_general_cluster")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
default_libraries = config_service.get_config("default_libraries")
custom_libraries = [
    {
        "whl": f"{artifacts_default_bucket}/reclameaqui-api-client-python/"
        "quintoandar_reclameaqui_api_client-0.1.0-py2.py3-none-any.whl"
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
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    cluster_configuration=cluster_description,
    libraries=custom_libraries + default_libraries,
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
    extraction_spark_job_file=raw_spark_jobs_path,
    raw_spark_job_extra_args=["{{ ds }}", SOURCE],
)

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    partitions=partition_cols,
)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_groups))

cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_groups),
    DatalakeTaskGroup.all_first_tasks(clean_task_groups),
)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
