import os
import pendulum
import json
from datetime import datetime

from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

SOURCE = "stilingue"
DAG_ID = f"bietlejuice.{SOURCE}"
local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2022, 4, 7, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(dag_name=SOURCE, env=ENV)

# s3 paths setup
ATHENA_QUERY_RESULTS_BUCKET = config_service.get_config("athena_query_results_bucket")
ARTIFACTS_S3_BUCKET = config_service.get_config("artifacts_bucket")
DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
S3_PREFIX = config_service.get_config("databricks_bietlejuice_repo_path")
RAW_SPARK_JOB_PATH = S3_PREFIX + f"/spark_jobs/{SOURCE}/load_{SOURCE}_into_datalake.py"
LOGS_OUTPUT_PATH = config_service.get_config("spark_jobs_logs_path")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
DOC_MD_BASE_URL = config_service.get_config("doc_md_chart_url")

SPARK_JOBS_LOGS_PATH = config_service.get_config("spark_jobs_logs_path")
DOC_MD_CHART_URL = config_service.get_config("doc_md_chart_url")
DATABRICKS_BIETLEJUICE_REPO_PATH = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)

CUSTOM_LIBRARIES = [
    {
        "whl": f"{ARTIFACTS_S3_BUCKET}/stilingue-api-client-python/"
        f"quintoandar_stilingue_api_client-0.1.1-py2.py3-none-any.whl"
    }
]

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_9_1_med_general_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{LOGS_OUTPUT_PATH}{DAG_ID}"

ENDPOINT_SCHEMA_EXCEPTIONS = config_service.get_config("endpoint_schema_exceptions")
TABLES = config_service.get_config("tables")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_SS,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=DOC_MD_CHART_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=CUSTOM_LIBRARIES,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    relative_query_path=SOURCE,
    spark_jobs_path=SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULTS_BUCKET,
)

raw_task_groups = {}
for TABLE_NAME, TABLE_DETAILS in TABLES.items():

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=TABLE_NAME,
        extraction_spark_job_file=RAW_SPARK_JOB_PATH,
        raw_spark_job_extra_args=[
            SOURCE,
            TABLE_NAME,
            "{{ ds }}",
            json.dumps(TABLE_DETAILS),
            json.dumps(ENDPOINT_SCHEMA_EXCEPTIONS),
        ],
    )
    raw_task_groups[TABLE_DETAILS["clean_table_name"]] = raw_task_group

    create_cluster_task >> DatalakeTaskGroup.first_tasks(raw_task_group)
    independent_tasks = DatalakeTaskGroup.independent_tasks(raw_task_group)
    if independent_tasks:
        terminate_cluster_task.set_upstream(independent_tasks)

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
)

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
