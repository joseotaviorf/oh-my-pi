from datetime import datetime
import pendulum

from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
import airflow.utils.helpers as airflow_helpers

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.bigfone_event import DAG_NAME

# dag params
DAG_ID = "bietlejuice.{}_historical_2019".format(DAG_NAME)
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 5, 20, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"
MAIN_END_DATE = datetime(2019, 10, 31, 0, 0, 0, tzinfo=LOCAL_TZ)

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
    end_date=MAIN_END_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    catchup=False,
    max_active_runs=1,
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

load_event_table_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load-event-table-to-clean",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": "{}/load_event_table_into_datalake_clean.py".format(
                SPARK_JOBS_PATH
            ),
            "parameters": ["{{ ds }}", ENV],
        }
    },
)

create_clean_partition_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-partition-on-events-table",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": "{}/create_partition_on_events_table.py".format(
                SPARK_JOBS_PATH
            ),
            "parameters": ["{{ ds }}", ENV],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

airflow_helpers.chain(
    create_cluster_task,
    load_event_table_to_raw_task,
    load_event_table_to_clean_task,
    create_clean_partition_task,
    terminate_cluster_task,
)
