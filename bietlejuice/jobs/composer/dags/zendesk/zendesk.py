from datetime import datetime
import pendulum
from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG

# dag params
DAG_ID = "bietlejuice.zendesk"
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 11, 1, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"
DEFAULT_PARTITION_BY = ["year", "month", "day"]
CHATS = "chats"
DEPARTMENTS = "departments"

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
        "whl": "s3://5a-artifacts/zendesk-client/quintoandar_zendesk_client-0.1.1-py3-none-any.whl"
    },
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES


def create_departments_sub_dag(sub_dag_name):
    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    zendesk_departments_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="zendesk-{}-to-datalake-raw".format(sub_dag_name),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": "{}/load_zendesk_departments_into_datalake_raw.py".format(
                    SPARK_JOBS_PATH
                ),
                "parameters": [DEPARTMENTS, "{{ ds }}", ENV],
            }
        },
    )

    create_zendesk_departments_clean_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="zendesk-{}-create-clean-external-tables".format(sub_dag_name),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": "{}/create_external_tables.py".format(SPARK_JOBS_PATH),
                "parameters": [ENV, "clean", DEPARTMENTS],
            }
        },
    )

    datalake_zendesk_departments_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="zendesk-{}-datalake-raw-to-clean-task".format(sub_dag_name),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": "{}/load_departments_data_to_clean.py".format(
                    SPARK_JOBS_PATH
                ),
                "parameters": [DEPARTMENTS, "{{ ds }}", ENV],
            }
        },
    )

    zendesk_departments_to_datalake_raw_task >> datalake_zendesk_departments_raw_to_clean_task >> create_zendesk_departments_clean_external_tables_task

    return local_dag


def create_chats_sub_dag(sub_dag_name, days_interval_start, days_interval_end):
    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    zendesk_chats_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="zendesk-{}-to-datalake-raw".format(sub_dag_name),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": "{}/load_zendesk_chats_into_datalake_raw.py".format(
                    SPARK_JOBS_PATH
                ),
                "parameters": [
                    CHATS,
                    "{{ ds }}",
                    days_interval_start,
                    days_interval_end,
                    ENV,
                ],
            }
        },
    )

    datalake_zendesk_chats_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="zendesk-{}-raw-to-clean-task".format(sub_dag_name),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": "{}/load_chats_data_to_clean.py".format(SPARK_JOBS_PATH),
                "parameters": [
                    CHATS,
                    "{{ ds }}",
                    days_interval_start,
                    days_interval_end,
                    ENV,
                ],
            }
        },
    )

    create_zendesk_chats_clean_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="zendesk-{}-create-clean-external-tables".format(sub_dag_name),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": "{}/create_external_tables.py".format(SPARK_JOBS_PATH),
                "parameters": [ENV, "clean", CHATS, "--partition_by"]
                + DEFAULT_PARTITION_BY,
            }
        },
    )

    zendesk_chats_to_datalake_raw_task >> datalake_zendesk_chats_raw_to_clean_task >> create_zendesk_chats_clean_external_tables_task

    return local_dag


dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=False,
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

create_sub_dag_task_departments_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag, sub_dag_name="departments", sub_dag_func=create_departments_sub_dag
)

create_sub_dag_task_chats_d1_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="chats-d1",
    sub_dag_func=create_chats_sub_dag,
    days_interval_start=1,
    days_interval_end=1,
)

# task to reprocess backwards (from D-2 to D-7) because old chats can have updates in some cases, for instance
# when it was missed and the ticket opened to solve it is updated
create_sub_dag_task_chats_d2_to_d7_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="chats-d2-to-d7",
    sub_dag_func=create_chats_sub_dag,
    days_interval_start=2,
    days_interval_end=7,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> create_sub_dag_task_chats_d1_task >> create_sub_dag_task_chats_d2_to_d7_task >> terminate_cluster_task
create_cluster_task >> create_sub_dag_task_departments_task >> terminate_cluster_task
