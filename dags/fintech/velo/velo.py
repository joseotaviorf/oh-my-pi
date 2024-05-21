import pendulum
from datetime import datetime
import os

from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers.task_flow_helper import TaskFlowHelper
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService

SOURCE = "velo"
DAG_NAME = SOURCE
DAG_ID = f"bietlejuice.{DAG_NAME}"

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2022, 10, 30, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(SOURCE)
datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"

cluster_description = config_service.get_config("databricks_10_4_med_general_cluster")
default_libraries = config_service.get_config("default_libraries")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

CUSTOM_LIBRARIES = [{"maven": {"coordinates": "mysql:mysql-connector-java:5.1.47"}}]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FINTECH,
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
    libraries=default_libraries + CUSTOM_LIBRARIES,
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

tables = config_service.get_config("tables")
partition_columns = config_service.get_config("partition_columns")

cleaned_tables = task_group._get_table_names_from_sql_files(LayerEnum.CLEAN)
raw_task_groups = {}
for table in tables:
    table_name = table["table_name"]
    extraction_type = table["extraction_type"]
    parameters = [SOURCE, table_name]

    is_incremental = extraction_type == "incremental"

    if is_incremental:
        parameters.append(table["date_filter_column"])
        parameters.append(table.get("unixtime_measure", "date"))
        parameters.append("{{ ds }}")

    raw_spark_job_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}//load_{extraction_type}_{SOURCE}_into_datalake.py"
    partitions = partition_columns if is_incremental else None

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        extraction_spark_job_file=raw_spark_job_path.format(
            extraction_type=extraction_type
        ),
        raw_spark_job_extra_args=parameters,
    )
    raw_task_groups[table_name] = raw_task_group

    create_cluster_task.set_downstream(DatalakeTaskGroup.first_tasks(raw_task_group))


clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
)

table_names = task_group._get_table_names_from_sql_files(layer=LayerEnum.CLEAN)

for table in table_names:
    TaskFlowHelper().cross_downstream_task_groups(
        raw_task_groups[table], clean_task_groups[table]
    )

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(raw_task_groups))
