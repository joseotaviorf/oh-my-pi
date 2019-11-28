from datetime import datetime
import pendulum
import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG

# dag params
DAG_ID = "zendesk"

ENV = Variable.get("environment")

# s3 vars
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

# spark_jobs path
SPARK_JOBS_PATH = S3_PREFIX + "/spark_jobs/zendesk"

# cluster params
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# databricks libraries
DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {
        "whl": "s3://5a-artifacts/tapioca-wrapper/tapioca_wrapper-quintoandar_1.5.1-py3-none-any.whl"
    },
    {
        "whl": "s3://5a-artifacts/zendesk-client/quintoandar_zendesk_client-0.1.0-py3-none-any.whl"
    },
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time

dag = DAG(
    dag_id="bietlejuice.{}".format(DAG_ID),
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime(2019, 11, 1, 0, 0, 0, tzinfo=local_tz),
    schedule_interval="0 4 * * *",
    max_active_runs=1,
    catchup=False,
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

zendesk_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="zendesk-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": "{}/load_zendesk_into_datalake_raw.py".format(
                SPARK_JOBS_PATH
            ),
            "parameters": ["chats", "{{ ds }}", 1, 1, ENV],
        }
    },
)

create_raw_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-raw-external-tables",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": "{}/create_raw_external_tables.py".format(SPARK_JOBS_PATH),
            "parameters": [ENV],
        }
    },
)

zendesk_to_datalake_raw_seven_days_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="zendesk-to-datalake-raw-seven-days",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": "{}/load_zendesk_into_datalake_raw.py".format(
                SPARK_JOBS_PATH
            ),
            "parameters": ["chats", "{{ ds }}", 2, 7, ENV],
        }
    },
)

create_raw_external_tables_seven_days_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-raw-external-tables-seven-days",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": "{}/create_raw_external_tables.py".format(SPARK_JOBS_PATH),
            "parameters": [ENV],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

airflow_helpers.chain(
    create_cluster_task,
    zendesk_to_datalake_raw_task,
    create_raw_external_tables_task,
    zendesk_to_datalake_raw_seven_days_task,
    create_raw_external_tables_seven_days_task,
    terminate_cluster_task,
)
