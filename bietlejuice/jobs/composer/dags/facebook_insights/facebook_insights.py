from datetime import datetime
import json
import os
import pendulum

from airflow.models import DAG
from airflow.models import Variable

import airflow.utils.helpers as airflow_helpers
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.base.datalake_sub_dag import DatalakeSubDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import FileService


# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG params setup
SOURCE = "marketing_costs"
MEDIA = "facebook_insights"
INSIGHTS_TABLE_NAME = MEDIA
SOCIAL_INSIGHTS_TABLE_NAME = "facebook_social_insights"
DAG_ID = f"bietlejuice.{MEDIA}"
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 6, 1, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"

# s3 paths setup
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_default_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
LOAD_FACEBOOK_CAMPAIGNS_INTO_DATALAKE_RAW_FILE_PATH = (
    S3_PREFIX + f"/spark_jobs/{MEDIA}/load_incremental_data_into_datalake_raw.py"
)
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{DAG_ID}"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base"

# cluster setup
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
CUSTOM_LIBRARIES = [
    {
        "whl": f"{ARTIFACTS_S3_BUCKET}/facebook-api-client-python/"
        f"quintoandar_facebook_api_client-0.1.2-py2.py3-none-any.whl"
    }
]

CONFIGS_YAML_PATH = os.path.join(
    os.path.dirname(os.path.realpath(__file__)), "facebook_insights_config.yaml"
)

CONFIGS = FileService.get_dict_from_yaml_file(CONFIGS_YAML_PATH)

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_ID).format(chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID),
)


create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=CUSTOM_LIBRARIES,
)

facebook_insights_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="facebook-insights-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_FACEBOOK_CAMPAIGNS_INTO_DATALAKE_RAW_FILE_PATH,
            "parameters": [
                ENV,
                SOURCE,
                MEDIA,
                DATALAKE_BUCKET,
                json.dumps(CONFIGS["accounts"]["general"]),
                json.dumps(CONFIGS["fields"]["general"]),
                json.dumps(CONFIGS["breakdowns"]["general"]),
                "{{ ds }}",
            ],
        }
    },
)

sync_metastore_facebook_insights_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-raw-facebook-insights",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "/sync_metastore_tables.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.RAW.value,
                SOURCE,
                "--table-name",
                INSIGHTS_TABLE_NAME,
            ],
        }
    },
)

validate_sync_metastore_facebook_insights_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id="validate-sync-hive-metastore-raw-facebook-insights",
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "/validate_sync_metastore_tables.py",
            "parameters": [
                LayerEnum.RAW.value,
                SOURCE,
                "--table-name",
                INSIGHTS_TABLE_NAME,
            ],
        }
    },
)

social_account_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="facebook-insights-social-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_FACEBOOK_CAMPAIGNS_INTO_DATALAKE_RAW_FILE_PATH,
            "parameters": [
                ENV,
                SOURCE,
                SOCIAL_INSIGHTS_TABLE_NAME,
                DATALAKE_BUCKET,
                json.dumps(CONFIGS["accounts"]["social"]),
                json.dumps(CONFIGS["fields"]["social"]),
                json.dumps(CONFIGS["breakdowns"]["social"]),
                "{{ ds }}",
            ],
        }
    },
)

sync_metastore_facebook_social_insights_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-raw-facebook-social-insights",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "/sync_metastore_tables.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.RAW.value,
                SOURCE,
                "--table-name",
                SOCIAL_INSIGHTS_TABLE_NAME,
            ],
        }
    },
)

validate_sync_metastore_facebook_social_insights_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id="validate-sync-hive-metastore-raw-facebook-social-insights",
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "/validate_sync_metastore_tables.py",
            "parameters": [
                LayerEnum.RAW.value,
                SOURCE,
                "--table-name",
                SOCIAL_INSIGHTS_TABLE_NAME,
            ],
        }
    },
)

clean_sub_dag = DatalakeSubDAG(
    dag_id=DAG_ID,
    start_date=MAIN_START_DATE,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    layer=LayerEnum.CLEAN,
    database_base_name=SOURCE,
    relative_query_path=f"{SOURCE}/{MEDIA}",
    spark_job_paths=SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

file_list = FileService.list_sql_files_without_extension_from_layer(
    f"{SOURCE}/{MEDIA}", LayerEnum.CLEAN.value
)

clean_sub_dags = clean_sub_dag.build_subdags_from_sql_files(
    dag, file_list, is_incremental=True, partitions=["year", "month", "day"]
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> facebook_insights_to_datalake_raw_task >> clean_sub_dags[
    INSIGHTS_TABLE_NAME
]

create_cluster_task >> social_account_to_datalake_raw_task >> clean_sub_dags[
    SOCIAL_INSIGHTS_TABLE_NAME
]

list(clean_sub_dags.values()) >> terminate_cluster_task

airflow_helpers.chain(
    facebook_insights_to_datalake_raw_task,
    sync_metastore_facebook_insights_task,
    validate_sync_metastore_facebook_insights_task,
    terminate_cluster_task,
)

airflow_helpers.chain(
    social_account_to_datalake_raw_task,
    sync_metastore_facebook_social_insights_task,
    validate_sync_metastore_facebook_social_insights_task,
    terminate_cluster_task,
)
