from datetime import datetime

from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.dummy_operator import DummyOperator
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
import airflow.utils.helpers as airflow_helpers

from bietlejuice.jobs.composer.base.airflow import BaseDAG

# dag params
DAG_ID = "bietlejuice.bigfone-event"
MAIN_START_DATE = datetime(2019, 9, 9, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = "0 4 * * *"

ENV = Variable.get("environment")

# s3 vars
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

# spark_jobs path
SPARK_JOBS_PATH = S3_PREFIX + "/spark_jobs/bigfone_event"

# cluster params
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# databricks libraries
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    catchup=False,
)

# ------------------------------ TASKS ------------------------------------------------ #
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

load_event_table_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load-event-table-to-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": "{}/load_event_table_into_datalake_raw.py".format(
                SPARK_JOBS_PATH
            ),
            "parameters": ["{{ ds }}", ENV],
        }
    },
)

move_data_to_clean_task = DummyOperator(task_id="move-data-to-clean", dag=dag)
create_clean_partition_task = DummyOperator(task_id="create-clean-partition", dag=dag)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

airflow_helpers.chain(
    create_cluster_task,
    load_event_table_to_raw_task,
    move_data_to_clean_task,
    create_clean_partition_task,
    terminate_cluster_task,
)
