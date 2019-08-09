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

DAG_ID = "insider"
ENV = Variable.get("environment")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

LOAD_INSIDER_INTO_DATALAKE_RAW_FILE_PATH = (
    S3_PREFIX + "/spark_jobs/{}/{}/load_insider_into_datalake.py".format(ENV, DAG_ID)
)
CREATE_RAW_EXTERNAL_TABLES_FILE_PATH = (
    S3_PREFIX + "/spark_jobs/{}/{}/create_raw_external_tables.py".format(ENV, DAG_ID)
)

LOGS_OUTPUT_PATH = "s3://5a-databricks/logs/jobs/{}".format(DAG_ID)

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz),
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

insider_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="insider-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_INSIDER_INTO_DATALAKE_RAW_FILE_PATH,
            "parameters": [ENV],
        }
    },
)

create_raw_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-raw-external-tables",
    dag=dag,
    json={"spark_python_task": {"python_file": CREATE_RAW_EXTERNAL_TABLES_FILE_PATH}},
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

airflow_helpers.chain(
    create_cluster_task,
    insider_to_datalake_raw_task,
    create_raw_external_tables_task,
    terminate_cluster_task,
)
