from datetime import datetime

import pendulum
import os
from airflow.utils.helpers import chain, cross_downstream
from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.dags.base.datalake_task_group import DatalakeTaskGroup


ENV = os.environ.get("ENVIRONMENT")

SOURCE = "survicate"
CONTEXT = SOURCE
DAG_NAME = f"{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 11, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "30 2 * * *"

config_service = ConfigurationService(dag_name=SOURCE)
partition_cols = config_service.get_config("partition_cols")

athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
artifacts_s3_bucket = config_service.get_config("artifacts_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
datalake_bucket = config_service.get_config("datalake_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

logs_output_path = f"s3://{databricks_bietlejuice_repo_path}/logs/jobs/{DAG_NAME}"
base_spark_job_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
raw_spark_job_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/load_survicate_into_datalake.py"

cluster_description = config_service.get_config("databricks_10_4_med_general_cluster")
custom_libraries = [
    {
        "whl": f"{artifacts_s3_bucket}/survicate-api-client-python/"
        f"quintoandar_survicate_api_client-0.1.0-py2.py3-none-any.whl"
    }
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_SS,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=custom_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=CONTEXT,
    spark_jobs_path=base_spark_job_path,
    athena_query_result_location=athena_query_results_bucket,
)

raw_task_groups = task_group.build_raw_task_group_for_all_tables(
    source=SOURCE,
    target_database_base_name=SOURCE,
    extraction_spark_job_file=raw_spark_job_path,
    raw_spark_job_extra_args=[SOURCE, "{{ ds }}"],
)

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    is_incremental=True,
    partitions=partition_cols,
)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_groups))

cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_groups),
    DatalakeTaskGroup.all_first_tasks(clean_task_groups),
)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
