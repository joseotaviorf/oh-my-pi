from datetime import datetime
from bietlejuice.jobs.composer.base.airflow.dag_owner_enum import DAGOwnerEnum
from pendulum import timezone
import os

from airflow.utils.helpers import chain
from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
from bietlejuice.jobs.composer.dags.base.reverse_task_group import ReverseTaskGroup
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

ENV = os.environ.get("ENVIRONMENT")
SOURCE = "nazare"
DAG_NAME = f"reverse_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2022, 7, 12, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))

config_service = ConfigurationService(DAG_NAME)

ARTIFACTS_S3_BUCKET = config_service.get_config("artifacts_bucket")
DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
DOC_MD_CHART_URL = config_service.get_config("doc_md_chart_url")
SPARK_JOBS_LOGS_PATH = config_service.get_config("spark_jobs_logs_path")
DATABRICKS_BIETLEJUICE_REPO_PATH = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)

BASE_SPARK_JOBS_PATH = f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/base/"
REVERSE_SPARK_JOB_PATH = f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/{DAG_NAME}/load_s3_data_into_external_bucket.py"

CLUSTER_DESCRIPTION = config_service.get_config("databricks_10_4_med_general_cluster")
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{SPARK_JOBS_LOGS_PATH}{DAG_ID}"
LIBRARIES_DESCRIPTION = config_service.get_config("default_libraries")

external_s3_bucket = config_service.get_config("external_s3_bucket")

PARTITIONS = ["year", "month", "day"]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FINTECH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_CHART_URL, dag_id=DAG_ID, ENV=ENV
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)


task_group = ReverseTaskGroup(
    dag=dag,
    env=ENV,
    s3_bucket=DATALAKE_BUCKET,
    relative_query_path=DAG_NAME,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
)

datalake_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.REVERSE,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    is_incremental=True,
    partitions=PARTITIONS,
)

external_bucket_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"load_s3_data_into_external_bucket",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": REVERSE_SPARK_JOB_PATH,
            "parameters": [ENV, DATALAKE_BUCKET, SOURCE, external_s3_bucket],
        }
    },
)


chain(create_cluster_task, ReverseTaskGroup.all_first_tasks(datalake_task_groups))
chain(ReverseTaskGroup.all_last_tasks(datalake_task_groups), external_bucket_task)
chain(external_bucket_task, terminate_cluster_task)
