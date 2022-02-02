from datetime import datetime
import pendulum
import os

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain

from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

SOURCE = "metabase"
CONTEXT = SOURCE

# airflow vars
ENV = os.environ.get("ENVIRONMENT")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

# spark and databricks vars
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{SOURCE}"
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_metabase_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# dag vars
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2020, 7, 27, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 5 * * *"
PARTITION_COLS = ["year", "month", "day"]

local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time

config_service = ConfigurationService(SOURCE)

# dag definition
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
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

raw_task_groups = {}
tables = config_service.get_config("tables")
for table in tables:
    table_name = table["table_name"]
    clean_table_name = table.get("clean_table_name", table_name)
    extraction_type = table["extraction_type"]
    parameters = [CONTEXT, table_name]

    if extraction_type == "incremental":
        parameters.extend([table["date_filter_column"], "{{ ds }}"])

    raw_spark_job_path = "{s3_prefix}/spark_jobs/{context}/load_{extraction_type}_data_into_datalake_raw.py".format(
        s3_prefix=S3_PREFIX, context=CONTEXT, extraction_type=extraction_type
    )
    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        table_name=table_name,
        target_database_base_name=CONTEXT,
        extraction_spark_job_file=raw_spark_job_path,
        raw_spark_job_extra_args=parameters,
    )
    raw_task_groups[clean_table_name] = raw_task_group

incremental_clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
    schema="incremental",  # TODO: we are misusing the schema here: incremental mode is not a schema
    is_incremental=True,
    partitions=PARTITION_COLS,
)

full_clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
    schema="full",  # TODO: we are misusing the schema here: full mode is not a schema
)

clean_task_groups = {**incremental_clean_task_groups, **full_clean_task_groups}

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups))

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
