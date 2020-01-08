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

DAG_ID = "terminator"
ENV = Variable.get("environment")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

LOAD_DATA_TO_RAW_FILE_PATH = S3_PREFIX + "/spark_jobs/{}/load_data_to_raw.py".format(
    DAG_ID
)

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time

dag = DAG(
    dag_id="bietlejuice.{}".format(DAG_ID),
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime(2020, 1, 1, 0, 0, 0, tzinfo=local_tz),
    schedule_interval="0 1 * * *",
    max_active_runs=1,
    catchup=False,
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

load_data_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load-data-to-raw-task",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_DATA_TO_RAW_FILE_PATH,
            "parameters": [ENV],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

airflow_helpers.chain(
    create_cluster_task, load_data_to_raw_task, terminate_cluster_task
)
