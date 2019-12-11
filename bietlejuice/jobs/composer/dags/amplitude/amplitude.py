from datetime import datetime
import pendulum
from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG

# variable definitions
DAG_ID = "bietlejuice.amplitude"
ENV = Variable.get("environment")
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 1, 1, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "30 23 * * *"
EVENT_TYPES = Variable.get("amplitude_event_types", deserialize_json=True)
DEFAULT_PARTITION_BY = ["year", "month", "day"]

# s3 paths setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
AMPLITUDE_SPARK_JOBS_PATH = "{}/spark_jobs/amplitude/".format(S3_PREFIX)
ADD_CLEAN_EVENTS_PARTITIONS_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "add_clean_events_partitions.py"
)
CREATE_ATHENA_EXTERNAL_TABLE_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "create_athena_external_table.py"
)
EVENTS_RAW_TO_CLEAN_FILE_PATH = AMPLITUDE_SPARK_JOBS_PATH + "events_raw_to_clean.py"
LOAD_EVENTS_INTO_DATALAKE_RAW_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "load_events_into_datalake_raw.py"
)
CREATE_CLEAN_FILTERED_EVENT_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "create_clean_filtered_event.py"
)
EVENTS_REPARTITIONED_RAW_TO_CLEAN_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "create_clean_incremental_table_in_datalake.py"
)
UPDATE_ATHENA_TABLE_DAILY_PARTITION_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "update_athena_table_daily_partition.py"
)
CREATE_CLEAN_STAGING_EVENTS_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "create_clean_staging_repartitioned_table.py"
)
CREATE_CLEAN_STAGING_SUBPARTITIONED_TABLES_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "create_clean_staging_subpartitioned_tables.py"
)
UPDATE_CLEAN_STAGING_SUBPARTITIONS_VALUES_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "update_clean_staging_table_subpartitions_values.py"
)
UPDATE_CLEAN_STAGING_SUBPARTITIONED_TABLES_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "update_clean_staging_subpartitioned_tables.py"
)
LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

# cluster configuration
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_memory_optimized_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# libraries dependencies
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)


# task builders
def create_clean_filtered_event_task(dag, event_type):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-{}-event-table".format(event_type.replace("_", "-")),
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": CREATE_CLEAN_FILTERED_EVENT_FILE_PATH,
                "parameters": ["{{ ds }}", ENV, event_type],
            }
        },
    )


def create_athena_external_table_task(dag, table_name, partition_by):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-{}-athena-external-table".format(table_name.replace("_", "-")),
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": CREATE_ATHENA_EXTERNAL_TABLE_FILE_PATH,
                "parameters": [ENV, table_name, "--partition_by"] + partition_by,
            }
        },
    )


def create_filtered_events_sub_dag(sub_dag_name):
    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()
    for event_type in EVENT_TYPES:
        t1 = create_clean_filtered_event_task(local_dag, event_type)
        table_name = "{}_events".format(event_type)
        t2 = create_athena_external_table_task(
            local_dag, table_name, DEFAULT_PARTITION_BY
        )
        t1 >> t2
    return local_dag


# Dag definition
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

# tasks definition
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

events_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="events-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_EVENTS_INTO_DATALAKE_RAW_FILE_PATH,
            "parameters": ["{{ ds }}", ENV],
        }
    },
)

events_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="events-raw-to-clean",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": EVENTS_RAW_TO_CLEAN_FILE_PATH,
            "parameters": ["{{ ds }}", ENV, "events", "--partition_by"]
            + DEFAULT_PARTITION_BY
            + ["event_type"],
        }
    },
)

add_clean_events_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="add-clean-events-partitions",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": ADD_CLEAN_EVENTS_PARTITIONS_FILE_PATH,
            "parameters": ["{{ ds }}", ENV],
        }
    },
)

create_filtered_events_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="create-filtered-events",
    sub_dag_func=create_filtered_events_sub_dag,
)


terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

events_repartitioned_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="events-repartitioned-raw-to-clean",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": EVENTS_REPARTITIONED_RAW_TO_CLEAN_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                "amplitude",
                "events_repartitioned",
                "--partition_by",
            ]
            + DEFAULT_PARTITION_BY,
        }
    },
)

update_clean_events_repartitioned_daily_partition_athena_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="update-clean-events-repartitioned-daily-partition-athena",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": UPDATE_ATHENA_TABLE_DAILY_PARTITION_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                "amplitude",
                "events_repartitioned",
                "clean",
            ],
        }
    },
)

create_clean_staging_events_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-clean-staging-events",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": CREATE_CLEAN_STAGING_EVENTS_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                "amplitude",
                "events_repartitioned",
                "events",
                "--partition_by",
            ]
            + ["id_app", "event_type"]
            + DEFAULT_PARTITION_BY,
        }
    },
)

update_clean_staging_subpartitions_values_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="update-clean-staging-subpartitions-values",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": UPDATE_CLEAN_STAGING_SUBPARTITIONS_VALUES_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                "amplitude",
                "events_repartitioned",
                "--subpartitions",
            ]
            + ["id_app", "event_type"],
        }
    },
)

create_clean_staging_subpartitioned_tables_spark_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-clean-staging-subpartitioned-tables-spark",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": CREATE_CLEAN_STAGING_SUBPARTITIONED_TABLES_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                "amplitude",
                "events_repartitioned",
                "events",
                "--spark",
            ],
        }
    },
)

create_clean_staging_subpartitioned_tables_athena_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-clean-staging-subpartitioned-tables-athena",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": CREATE_CLEAN_STAGING_SUBPARTITIONED_TABLES_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                "amplitude",
                "events_repartitioned",
                "events",
                "--athena",
            ],
        }
    },
)

update_clean_staging_subpartitioned_tables_spark_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="update-clean-staging-subpartitioned-tables-spark",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": UPDATE_CLEAN_STAGING_SUBPARTITIONED_TABLES_FILE_PATH,
            "parameters": ["{{ ds }}", ENV, "amplitude", "--spark"],
        }
    },
)

update_clean_staging_subpartitioned_tables_athena_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="update-clean-staging-subpartitioned-tables-athena",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": UPDATE_CLEAN_STAGING_SUBPARTITIONED_TABLES_FILE_PATH,
            "parameters": ["{{ ds }}", ENV, "amplitude", "--athena"],
        }
    },
)

# tasks dependencies definition
create_cluster_task >> events_to_datalake_raw_task >> [
    events_raw_to_clean_task,
    events_repartitioned_raw_to_clean_task,
]

events_raw_to_clean_task >> [
    add_clean_events_partitions_task,
    create_filtered_events_sub_dag_task,
] >> terminate_cluster_task

events_repartitioned_raw_to_clean_task >> update_clean_events_repartitioned_daily_partition_athena_task
update_clean_events_repartitioned_daily_partition_athena_task >> terminate_cluster_task
events_repartitioned_raw_to_clean_task >> [
    create_clean_staging_events_task,
    update_clean_staging_subpartitions_values_task,
] >> create_clean_staging_subpartitioned_tables_spark_task
create_clean_staging_subpartitioned_tables_spark_task >> [
    create_clean_staging_subpartitioned_tables_athena_task,
    update_clean_staging_subpartitioned_tables_spark_task,
] >> terminate_cluster_task
create_clean_staging_subpartitioned_tables_athena_task >> update_clean_staging_subpartitioned_tables_athena_task
update_clean_staging_subpartitioned_tables_athena_task >> terminate_cluster_task
