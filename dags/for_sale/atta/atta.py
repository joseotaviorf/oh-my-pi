import pendulum
from datetime import datetime
import os

from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import cross_downstream

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

SOURCE = "atta"
DAG_NAME = SOURCE
DAG_ID = f"bietlejuice.{DAG_NAME}"

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2022, 9, 20, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 3 * * *"
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(SOURCE)
datalake_bucket = config_service.get_config("datalake_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"

cluster_description = config_service.get_config("databricks_10_4_med_io-general_cluster")
default_libraries = config_service.get_config("default_libraries")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

CUSTOM_LIBRARIES = [
    {"jar": f"{artifacts_bucket}/mysql-connector-java/mysql-connector-java-5.1.47.jar"}
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_SALE,
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
partition_columns = config_service.get_config("clean_partition_columns")

for table in tables:
    table_name = table["table_name"]
    clean_table_name = table["clean_table_name"]
    extraction_type = table["extraction_type"]
    parameters = [SOURCE, table_name, table["db"]]

    is_incremental = extraction_type == "incremental"

    if is_incremental:
        parameters.append(table["date_filter_column"])
        parameters.append(str(partition_columns))
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

    create_cluster_task.set_downstream(DatalakeTaskGroup.first_tasks(raw_task_group))

    clean_table_name = table.get("clean_table_name", clean_table_name)
    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=clean_table_name,
        is_incremental=is_incremental,
        partitions=partitions,
    )

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
