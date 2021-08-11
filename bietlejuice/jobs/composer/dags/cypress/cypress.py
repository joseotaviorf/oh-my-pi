from datetime import datetime
from pendulum import timezone
import os

from airflow.utils.helpers import chain, cross_downstream
from airflow.models import DAG, Variable
from airflow.operators.sensors import S3KeySensor
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)


SOURCE = "cypress"
DAG_ID = f"bietlejuice.{SOURCE}"
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(SOURCE)
ATHENA_QUERY_RESULTS_BUCKET = config_service.get_config("athena_query_results_bucket")
DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
DATABRICKS_BIETLEJUICE_REPO_PATH = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
SPARK_JOBS_LOGS_PATH = config_service.get_config("spark_jobs_logs_path")
DOC_MD_CHART_URL = config_service.get_config("doc_md_chart_url")

PARTITION_COLS = config_service.get_config("partition_cols")
TABLES_LIST = config_service.get_config("tables_list")
CYPRESS_SOURCE_BUCKET = config_service.get_config("cypress_source_bucket")

MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "15 7 * * *"
RAW_SPARK_JOB_FILE = (
    f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/{SOURCE}/load_cypress_raw.py"
)
BASE_SPARK_JOBS_PATH = f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/base/"

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["spark_env_vars"]["ENVIRONMENT"] = ENV
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{SPARK_JOBS_LOGS_PATH}{DAG_ID}"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=DOC_MD_CHART_URL, dag_id=DAG_ID
    ),
)

check_s3_objects_task = S3KeySensor(
    task_id="check-s3-objects",
    poke_interval=0,
    timeout=10,
    soft_fail=True,
    aws_conn_id="aws_default",
    wildcard_match=True,
    bucket_name=CYPRESS_SOURCE_BUCKET,
    bucket_key="*/{{ ds }}/*/*.json",
    dag=dag,
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    relative_query_path=SOURCE,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULTS_BUCKET,
)

for table_name in TABLES_LIST:

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        extraction_spark_job_file=RAW_SPARK_JOB_FILE,
        raw_spark_job_extra_args=[SOURCE, table_name, "{{ ds }}"],
    )

    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        is_incremental=True,
        partitions=PARTITION_COLS,
    )

    chain(
        check_s3_objects_task,
        create_cluster_task,
        DatalakeTaskGroup.first_tasks(raw_task_group),
    )

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
