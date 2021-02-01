import os
import pendulum
import json
from datetime import datetime

from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.services import FileService

# ENV setup
ENV = Variable.get("environment")

# DAG params setup
SOURCE = "gsheets"
DAG_ID = f"bietlejuice.{SOURCE}"
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2021, 1, 14, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"

# s3 paths setup
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_default_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
LOAD_GSHEETS_INTO_DATALAKE_RAW_FILE_PATH = (
    S3_PREFIX + f"/spark_jobs/{SOURCE}/load_full_data_into_datalake_raw.py"
)
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{DAG_ID}"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base"

# cluster setup
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

CUSTOM_LIBRARIES = [
    {
        "whl": f"{ARTIFACTS_S3_BUCKET}/gsheets-api-client-python/"
        f"quintoandar_gsheets_api_client-0.1.0-py2.py3-none-any.whl"
    }
]

GOOGLE_FILES_YAML_PATH = os.path.join(
    os.path.dirname(os.path.realpath(__file__)), "gsheets_files.yaml"
)

GOOGLE_FILES = FileService.get_dict_from_yaml_file(GOOGLE_FILES_YAML_PATH)

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=CUSTOM_LIBRARIES,
)

gsheets_to_datalake_raw_tasks = []

for TABLE_NAME, SHEET_DETAILS in GOOGLE_FILES.items():

    slugged_table_name = TABLE_NAME.replace("_", "-")

    task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"gsheets-{slugged_table_name}-to-datalake-raw",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": LOAD_GSHEETS_INTO_DATALAKE_RAW_FILE_PATH,
                "parameters": [
                    ENV,
                    SOURCE,
                    DATALAKE_BUCKET,
                    TABLE_NAME,
                    json.dumps(SHEET_DETAILS),
                ],
            }
        },
    )

    gsheets_to_datalake_raw_tasks.append(task)


terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> gsheets_to_datalake_raw_tasks >> terminate_cluster_task
