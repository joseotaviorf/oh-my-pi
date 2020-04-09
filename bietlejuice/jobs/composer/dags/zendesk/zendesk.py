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
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.dags.zendesk import (
    CHATS,
    DEPARTMENTS,
    DEPARTMENTS_WITH_PREFIX,
    CHAT_ENGAGEMENTS,
    QUERIES_ZENDESK_DATALAKE_PATH,
    DW_SCHEMA,
    SOURCE,
)


# dag params
DAG_ID = f"bietlejuice.{SOURCE}"
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 11, 1, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 1 * * *"
DEFAULT_PARTITION_BY = ["year", "month", "day"]

ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
DATABRICKS_S3_BUCKET = Variable.get("databricks_s3_bucket")

# s3 vars
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
DW_BUCKET = Variable.get("dw_bucket")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")

LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_S3_BUCKET}/logs/jobs/{DAG_ID}"

# spark_jobs path
SPARK_JOBS_PATH = S3_PREFIX + f"/spark_jobs/{SOURCE}"

# cluster params
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_memory_optimized_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# databricks libraries
DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {
        "whl": f"{ARTIFACTS_S3_BUCKET}/tapioca-wrapper/tapioca_wrapper-quintoandar_1.5.1-py3-none-any.whl"
    },
    {
        "whl": f"{ARTIFACTS_S3_BUCKET}/zendesk-client/quintoandar_zendesk_client-0.1.1-py3-none-any.whl"
    },
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
)


def create_departments_sub_dag(sub_dag_name):
    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    zendesk_departments_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"zendesk-{sub_dag_name}-to-datalake-raw",
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/load_zendesk_departments_into_datalake_raw.py",
                "parameters": [DEPARTMENTS, "{{ ds }}", ENV, DATALAKE_BUCKET],
            }
        },
    )

    create_zendesk_departments_clean_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"zendesk-{sub_dag_name}-create-clean-external-tables",
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/create_external_tables.py",
                "parameters": [
                    ENV,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                    "clean",
                    DEPARTMENTS_WITH_PREFIX,
                ],
            }
        },
    )

    datalake_zendesk_departments_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"zendesk-{sub_dag_name}-datalake-raw-to-clean-task",
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/load_departments_data_to_clean.py",
                "parameters": [
                    DEPARTMENTS_WITH_PREFIX,
                    "{{ ds }}",
                    ENV,
                    DATALAKE_BUCKET,
                ],
            }
        },
    )

    zendesk_departments_to_datalake_raw_task >> datalake_zendesk_departments_raw_to_clean_task >> create_zendesk_departments_clean_external_tables_task

    return local_dag


def create_chat_engagements_sub_dag(
    sub_dag_name, days_interval_start, days_interval_end
):
    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    datalake_zendesk_chat_engagements_clean_to_enrich_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"zendesk-{sub_dag_name}-clean-to-enrich-task",
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/load_incremental_data_to_metastore.py",
                "parameters": [
                    CHAT_ENGAGEMENTS,
                    "{{ ds }}",
                    days_interval_start,
                    days_interval_end,
                    ENV,
                    DATALAKE_BUCKET,
                    "clean",
                    "enrich",
                ],
            }
        },
    )

    create_zendesk_chat_engagements_enrich_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"zendesk-{sub_dag_name}-create-enrich-external-tables",
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/create_external_tables.py",
                "parameters": [
                    ENV,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                    "enrich",
                    CHAT_ENGAGEMENTS,
                    "--partition_by",
                ]
                + DEFAULT_PARTITION_BY,
            }
        },
    )

    datalake_zendesk_chat_engagements_clean_to_enrich_task >> create_zendesk_chat_engagements_enrich_external_tables_task

    return local_dag


def create_chats_sub_dag(sub_dag_name, days_interval_start, days_interval_end):
    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    zendesk_chats_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"zendesk-{sub_dag_name}-to-datalake-raw",
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/load_zendesk_chats_into_datalake_raw.py",
                "parameters": [
                    CHATS,
                    "{{ ds }}",
                    days_interval_start,
                    days_interval_end,
                    ENV,
                    DATALAKE_BUCKET,
                ],
            }
        },
    )

    datalake_zendesk_chats_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"zendesk-{sub_dag_name}-raw-to-clean-task",
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/load_incremental_data_to_metastore.py",
                "parameters": [
                    CHATS,
                    "{{ ds }}",
                    days_interval_start,
                    days_interval_end,
                    ENV,
                    DATALAKE_BUCKET,
                    "raw",
                    "clean",
                ],
            }
        },
    )

    create_zendesk_chats_clean_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"zendesk-{sub_dag_name}-create-clean-external-tables",
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/create_external_tables.py",
                "parameters": [
                    ENV,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                    "clean",
                    CHATS,
                    "--partition_by",
                ]
                + DEFAULT_PARTITION_BY,
            }
        },
    )

    zendesk_chats_to_datalake_raw_task >> datalake_zendesk_chats_raw_to_clean_task >> create_zendesk_chats_clean_external_tables_task
    return local_dag


def dw_tasks(sub_dag_name, table_name, slugged_table_name):

    sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    create_table_in_dw_staging = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"load-{slugged_table_name}-into-dw-{DW_SCHEMA}-staging",
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/load_full_data_to_staging.py",
                "parameters": [DW_BUCKET, table_name, ENV],
            }
        },
    )

    create_table_in_dw = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"load-{slugged_table_name}-into-dw-{DW_SCHEMA}",
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/load_full_table_to_dw.py",
                "parameters": [DW_BUCKET, table_name, ENV],
            }
        },
    )

    load_dw_table_into_redshift = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"load-{slugged_table_name}-into-redshift",
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/load_full_table_to_redshift.py",
                "parameters": [DW_BUCKET, table_name, ENV, SPECTRUM_IAM_ROLE],
            }
        },
    )

    create_table_in_dw_staging >> create_table_in_dw >> load_dw_table_into_redshift

    return sub_dag


def build_sub_dags(target_layer):
    # create subdag for each table
    file_list = FileService.list_files(
        f"{QUERIES_ZENDESK_DATALAKE_PATH}/{target_layer}/"
    )
    subdags = {}

    for file_name in file_list:
        file_name = FileService.remove_file_extension(file_name)
        slugged_table_name = file_name.replace("_", "-")
        table_sub_dag = BaseSubDAG.get_sub_dag_operator(
            dag=dag,
            sub_dag_name=f"load-{slugged_table_name}-to-{target_layer}",
            sub_dag_func=eval(f"{target_layer}_tasks"),
            table_name=file_name,
            slugged_table_name=slugged_table_name,
        )
        subdags[file_name] = table_sub_dag

    # subdags is a dict where the keys are table or file names
    # and the values are corresponding subdag objects
    return subdags


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

create_sub_dag_task_chat_engagements_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="chat-engagements",
    sub_dag_func=create_chat_engagements_sub_dag,
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

dw_full_tables_sub_dag = build_sub_dags(target_layer="dw")


# incremental flow
create_cluster_task >> [
    create_sub_dag_task_chats_d1_task,
    create_sub_dag_task_departments_task,
]
create_sub_dag_task_chats_d1_task >> create_sub_dag_task_chats_d2_to_d7_task >> [
    create_sub_dag_task_chat_engagements_task,
    dw_full_tables_sub_dag["dim_chat"],
]
create_sub_dag_task_departments_task >> [
    dw_full_tables_sub_dag["dim_chat_department"],
    dw_full_tables_sub_dag["dim_chat_engagement"],
]
create_sub_dag_task_chat_engagements_task >> [
    dw_full_tables_sub_dag["dim_chat_engagement"],
    dw_full_tables_sub_dag["fact_chat_engagements"],
]
list(dw_full_tables_sub_dag.values()) >> terminate_cluster_task
