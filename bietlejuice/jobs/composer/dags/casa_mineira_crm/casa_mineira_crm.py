from datetime import datetime

import json
import pendulum
import os

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain, cross_downstream
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.services import FileService


ENV = os.environ.get("ENVIRONMENT")
CONFIGS_FILE_PATH = f"{os.path.dirname(os.path.realpath(__file__))}/{ENV}_config.yaml"

configs_file = FileService.get_dict_from_yaml_file(CONFIGS_FILE_PATH)
SOURCE = configs_file.get("dag_name")
CONTEXT = SOURCE

DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 11, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "30 0 * * *"

ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{SOURCE}"
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
RAW_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}"
RAW_SPARK_JOB_PATH = (
    f"{S3_PREFIX}/spark_jobs/{CONTEXT}/load_{CONTEXT}_into_datalake_raw.py"
)

CLUSTER_DESCRIPTION = Variable.get(f"databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH


dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID),
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
    relative_query_path=CONTEXT,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

source_root_path = configs_file.get("source_root_path")
source_path_template = configs_file.get("source_path_template")
job_extra_args = configs_file.get("job_extra_args", {})
parameters = [
    CONTEXT,
    source_root_path,
    source_path_template,
    json.dumps(job_extra_args),
]

raw_task_groups = task_group.build_raw_task_group_for_all_tables(
    source=SOURCE,
    target_database_base_name=CONTEXT,
    extraction_spark_job_file=RAW_SPARK_JOB_PATH,
    raw_spark_job_extra_args=parameters,
)


clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
    schema="full",  # TODO: we are misusing the schema here: full mode is not a schema
)


chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_groups))

cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_groups),
    DatalakeTaskGroup.all_first_tasks(clean_task_groups),
)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
