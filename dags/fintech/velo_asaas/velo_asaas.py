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

SOURCE = "velo_asaas"
DAG_NAME = SOURCE
DAG_ID = f"bietlejuice.{DAG_NAME}"

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2022, 1, 9, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 4 * * 1"
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(SOURCE)
datalake_bucket = config_service.get_config("datalake_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/load_{SOURCE}_into_datalake.py"

CLUSTER_DESCRIPTION = config_service.get_config("custom_cluster")


CLUSTER_DESCRIPTION["data_security_mode"] = "SINGLE_USER"
CLUSTER_DESCRIPTION["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
CLUSTER_DESCRIPTION["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = "quintoandar_{{ var.value.environment }}"
default_libs = config_service.get_config("default_libraries")
custom_libs = config_service.get_config("cluster_libs")
custom_libs[0]["whl"] = custom_libs[0]["whl"].format(artifacts_bucket=artifacts_bucket)

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

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=default_libs + custom_libs,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(databricks_conn_id="databricks_new", dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(databricks_conn_id="databricks_new", dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=SOURCE,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    execution_timeout_hours=3
)

tables = config_service.get_config("tables")
partition_columns = config_service.get_config("partition_columns")

for table in tables:
    table_name = table["table_name"]
    extraction_type = table["extraction_type"]
    is_incremental = extraction_type == "incremental"

    api_consumer_id = table["api_consumer_id"]
    consumer_args = table.get("consumer_args","{}")
    parameters = [SOURCE, extraction_type, table_name, api_consumer_id, consumer_args, "{{ ds }}"]

    partitions = partition_columns if is_incremental else None

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        extraction_spark_job_file=RAW_SPARK_JOB_PATH,
        raw_spark_job_extra_args=parameters,
    )

    create_cluster_task.set_downstream(
        DatalakeTaskGroup.first_tasks(raw_task_group)
    )

    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        is_incremental=is_incremental,
        partitions=partitions,
    )
    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
