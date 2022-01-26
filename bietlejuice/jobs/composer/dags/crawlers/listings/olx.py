import os
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
import pendulum
from datetime import datetime, time, timedelta

from airflow.utils.helpers import chain, cross_downstream
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

SOURCE = "crawlers"
CONTEXT = f"listings"
ORIGIN = f"olx"
DAG_NAME = f'{ORIGIN}'
SOURCE_WITH_CONTEXT = f'{SOURCE}_{CONTEXT}'
DAG_ID = f"bietlejuice.{DAG_NAME}"
INTERMEDIATE_PATH = f'{SOURCE}/{CONTEXT}'
CONFIG_NAME = 'crawlers_listings'
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
ENV = os.environ.get("ENVIRONMENT")
MAIN_START_DATE = datetime(2021, 7, 20, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 3 * * 5"

config_service = ConfigurationService(dag_name = CONFIG_NAME, intermediate_path=INTERMEDIATE_PATH)

olx_configs = config_service.get_config("olx")
origin = olx_configs["origin"]

athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{INTERMEDIATE_PATH}"

CLUSTER_DESCRIPTION = Variable.get(f"databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["spark_env_vars"]["ENVIRONMENT"] = ENV
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{spark_jobs_logs_path}{DAG_ID}"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
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
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
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

partition_cols = config_service.get_config("partition_cols")


raw_spark_job_path = f"{RAW_SPARK_JOB_PATH}/load_crawlers_listings_into_datalake.py"
parameters = [SOURCE,CONTEXT, origin, origin, "{{ds}}"]


raw_task_group = task_group.build_raw_task_group_for_single_table(
    source=SOURCE_WITH_CONTEXT,
    table_name=origin,
    target_database_base_name=SOURCE_WITH_CONTEXT,
    extraction_spark_job_file=raw_spark_job_path,
    raw_spark_job_extra_args=parameters,
)

clean_task_group = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE_WITH_CONTEXT,
    target_database_base_name=SOURCE_WITH_CONTEXT,
    tree_path = f'{CONTEXT}/{DAG_NAME}/',
    partitions=partition_cols
)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_group),
    DatalakeTaskGroup.all_first_tasks(clean_task_group),
)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_group))