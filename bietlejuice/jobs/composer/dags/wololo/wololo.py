from datetime import datetime

import airflow.utils.helpers as airflow_helpers
import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG

DAG_ID = "wololo"
ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

LOAD_WOLOLO_INTO_DATALAKE_RAW_FILE_PATH = (
    S3_PREFIX + "/spark_jobs/{}/load_wololo_into_datalake.py".format(DAG_ID)
)
CREATE_RAW_EXTERNAL_TABLES_FILE_PATH = (
    S3_PREFIX + "/spark_jobs/{}/create_raw_external_tables.py".format(DAG_ID)
)

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_wololo", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"

dag = DAG(
    dag_id="bietlejuice.{}".format(DAG_ID),
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

wololo_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="wololo-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_WOLOLO_INTO_DATALAKE_RAW_FILE_PATH,
            "parameters": [ENV, DATALAKE_BUCKET],
        }
    },
)

create_raw_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-raw-external-tables",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": CREATE_RAW_EXTERNAL_TABLES_FILE_PATH,
            "parameters": [ENV, DATALAKE_BUCKET, ATHENA_QUERY_RESULT_LOCATION],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

airflow_helpers.chain(
    create_cluster_task,
    wololo_to_datalake_raw_task,
    create_raw_external_tables_task,
    terminate_cluster_task,
)
