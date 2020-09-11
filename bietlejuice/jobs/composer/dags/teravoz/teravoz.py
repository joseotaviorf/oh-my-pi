from datetime import datetime, timedelta

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.jobs.composer.dags.teravoz import SOURCE
from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG

# dag params
DAG_ID = "bietlejuice.{}".format(SOURCE)
MAIN_START_DATE = datetime(2019, 7, 12, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = "0 4 * * *"

ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")

# s3 vars
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

# spark_jobs path
SPARK_JOBS_PATH = S3_PREFIX + "/spark_jobs/{}".format(SOURCE)

# cluster params
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# databricks libraries
DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {
        "whl": f"{ARTIFACTS_S3_BUCKET}/tapioca-wrapper/tapioca_wrapper-quintoandar_1.5.1-py3-none-any.whl"
    },
    {
        "whl": f"{ARTIFACTS_S3_BUCKET}/teravoz-client/quintoandar_teravoz_client-0.1.5-py3-none-any.whl"
    },
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
        "retries": 3,
        "retry_delay": timedelta(minutes=5),
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
)


def raw_tasks(sub_dag_name, local_dag):

    request_api_and_load_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="request-api-load-to-raw",
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": "{}/load_{}_into_datalake_raw.py".format(
                    SPARK_JOBS_PATH, SOURCE
                ),
                "parameters": [sub_dag_name, "{{ ds }}", ENV, DATALAKE_BUCKET],
            }
        },
    )

    raw_tasks_list = [request_api_and_load_to_raw_task]
    return raw_tasks_list


def clean_tasks(sub_dag_name, local_dag):

    load_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="move-data-to-clean",
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": "{}/load_data_to_clean.py".format(SPARK_JOBS_PATH),
                "parameters": [
                    sub_dag_name,
                    "{{ ds }}",
                    ENV,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                ],
            }
        },
    )

    create_clean_partition_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-clean-partition",
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": "{}/create_external_table.py".format(SPARK_JOBS_PATH),
                "parameters": [
                    sub_dag_name,
                    "{{ ds }}",
                    ENV,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                ],
            }
        },
    )

    clean_tasks_list = [load_to_clean_task, create_clean_partition_task]
    return clean_tasks_list


def sub_dag(sub_dag_name):

    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    list_tasks = raw_tasks(sub_dag_name, local_dag)
    list_tasks += clean_tasks(sub_dag_name, local_dag)

    airflow_helpers.chain(
        list_tasks[0],  # request_api_and_load_to_raw_task
        list_tasks[1],  # load_to_clean_task
        list_tasks[2],  # create_clean_partition_task
    )

    return local_dag


def raw_sub_dag(sub_dag_name):

    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    list_tasks = raw_tasks(sub_dag_name, local_dag)
    airflow_helpers.chain(list_tasks[0])  # request_api_and_load_to_raw_task

    return local_dag


create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)


def clean_sub_dag(sub_dag_name):

    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    list_tasks = clean_tasks(sub_dag_name, local_dag)

    airflow_helpers.chain(
        list_tasks[0],  # load_to_clean_task
        list_tasks[1],  # create_clean_partition_task
    )
    return local_dag


queues_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag, sub_dag_name="queues", sub_dag_func=sub_dag
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> queues_sub_dag_task >> terminate_cluster_task
