from datetime import datetime
import pendulum
import os
from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG params setup
SOURCE = "marketing_costs"
MEDIA = "twitter"
DAG_ID = f"bietlejuice.{MEDIA}"
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 6, 1, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 4 * * *"

DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

# s3 paths setup
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_default_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
LOAD_TWITTER_INTO_DATALAKE_RAW_FILE_PATH = (
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
        "whl": f"{ARTIFACTS_S3_BUCKET}/twitter-api-client-python/"
        f"quintoandar_twitter_api_client-0.1.1-py2.py3-none-any.whl"
    }
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(MEDIA).format(chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID),
)


create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=CUSTOM_LIBRARIES,
)

twitter_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="twitter-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_TWITTER_INTO_DATALAKE_RAW_FILE_PATH,
            "parameters": [ENV, SOURCE, MEDIA, DATALAKE_BUCKET, "{{ ds }}"],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> twitter_to_datalake_raw_task >> terminate_cluster_task
