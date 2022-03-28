import os
from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.operators.quintoandar_transfer_data import QuintoAndarMySqlToS3Operator
from airflow.utils.helpers import cross_downstream

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.db import DATALAKE_SQL_DIR
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.formatters import StringFormatter
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

SOURCE = "composer"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 8, 21, 0, 0, 0, tzinfo=LOCAL_TZ)
SCHEDULE_INTERVAL = "30 6 * * *"

ENV = os.environ.get("ENVIRONMENT")


config_service = ConfigurationService(SOURCE)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

clean_partition_cols = config_service.get_config("clean_partition_cols")
tables = config_service.get_config("tables")

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/load_{{extraction_type}}_{SOURCE}_into_datalake.py"

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_9_1_min_general_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["spark_env_vars"]["ENVIRONMENT"] = ENV
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{spark_jobs_logs_path}{DAG_ID}"


QUERY_PATH = "{datalake_sql_dir}/queries/composer/raw/{table_name}.sql"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)


def get_sql_from_table_name(table_name):
    """
    Search and get a sql given a table_name

    :param table_name: table name
    :type table_name: str
    :return: the query to built the given table.
    :rtype: str
    """
    sql = FileService.get_query_from_file_name(
        QUERY_PATH.format(datalake_sql_dir=DATALAKE_SQL_DIR, table_name=table_name)
    )
    return sql


def create_extraction_tasks(table_name, has_query=False, is_incremental=False):
    """
    Create a task to load table from Airflow database to S3.
    In this way, the first step of raw creation is executed
    outside a spark job. When incremental is used, this functions
    breaks the load in two to keep a d-1 ingestion, but to add
    a fraction of today data (This happens to keep data fresh for
    some pulses).

    :param table_name: table name
    :type table_name: str
    :param has_query: if a query will be used or the table will be consumed asis
    :type has_query: bool
    :param is_incremental: if this table will be consumed incremental
    :type is_incremental: bool
    :return: An airflow task
    :rtype: BaseOperator
    """
    slugged_table_name = StringFormatter.slugify(table_name)

    if is_incremental:
        s3_suffix = "/year={{ execution_date.year }}/month={{ execution_date.month }}/day={{ execution_date.day }}"
    else:
        s3_suffix = ""

    sql = get_sql_from_table_name(table_name) if has_query else None

    if sql and is_incremental:
        sql = sql.format(start_date="{{ ds }}")

    raw_task = QuintoAndarMySqlToS3Operator(
        dag=dag,
        table=table_name,
        sql=sql,
        task_id=f"load-raw-to-s3-{slugged_table_name}",
        bucket=datalake_bucket,
        filename="data.json",
        s3_file_path="raw/composer/{table_name}{s3_suffix}".format(
            table_name=table_name, s3_suffix=s3_suffix
        ),
        mysql_conn_id="airflow_db",
    )

    return raw_task


create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=CONTEXT,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)


for table_name, table_config in tables.items():
    table_config = table_config if table_config else {}
    is_incremental = table_config.get("is_incremental", False)
    is_partitioned = table_config.get("is_partitioned")
    has_query = table_config.get("has_query")
    extraction_type = "incremental" if is_incremental else "full"

    load_raw_to_s3_task = create_extraction_tasks(
        table_name=table_name, is_incremental=is_incremental, has_query=has_query
    )

    parameters = [SOURCE, table_name]
    if is_incremental:
        parameters.append("{{ ds }}")

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        extraction_spark_job_file=RAW_SPARK_JOB_PATH.format(
            extraction_type=extraction_type
        ),
        raw_spark_job_extra_args=parameters,
    )

    partitions = clean_partition_cols if is_partitioned else None
    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        is_incremental=is_incremental,
        partitions=partitions,
    )

    create_cluster_task.set_upstream(load_raw_to_s3_task)
    create_cluster_task.set_downstream(DatalakeTaskGroup.first_tasks(raw_task_group))

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
