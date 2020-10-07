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

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG
from bietlejuice.jobs.composer.dags.bigfone_event import (
    DAG_NAME,
    DW_SCHEMA,
    QUERIES_BIGFONE_EVENT_DATALAKE_PATH,
)

# dag params
from bietlejuice.jobs.composer.services import FileService

DAG_ID = "bietlejuice.{}_reprocess".format(DAG_NAME)
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 9, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 4 * * *"


ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
DATALAKE_OLD_BUCKET = Variable.get("datalake_old_bucket")
DW_BUCKET = Variable.get("dw_bucket")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")

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
    catchup=True,
    max_active_runs=1,
)


def enrich_tasks(sub_dag_name, table_name, slugged_table_name):

    sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    load_enrich_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"create-enrich-{slugged_table_name}-in-data-lake",
        dag=sub_dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/load_incremental_to_datalake_layer.py",
                "parameters": [
                    ENV,
                    "{{ ds }}",
                    DATALAKE_BUCKET,
                    "clean",
                    "enrich",
                    table_name,
                ],
            }
        },
    )

    create_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"create-enrich-{slugged_table_name}-external-table",
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/create_incremental_external_table.py",
                "parameters": [
                    ENV,
                    "{{ ds }}",
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                    "enrich",
                    table_name,
                ],
            }
        },
    )

    load_enrich_table_task >> create_external_table_task

    return sub_dag


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
                "python_file": f"{SPARK_JOBS_PATH}/create_table_in_dw_staging.py",
                "parameters": [DW_BUCKET, table_name, ENV],
            }
        },
    )

    create_table_in_dw = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"load-{slugged_table_name}-into-dw-{DW_SCHEMA}",
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/create_table_in_dw.py",
                "parameters": [DW_BUCKET, table_name, ENV],
            }
        },
    )

    load_dw_table_into_redshift = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"load-{slugged_table_name}-into-redshift",
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}/load_dw_table_into_redshift.py",
                "parameters": [DW_BUCKET, table_name, ENV, SPECTRUM_IAM_ROLE],
            }
        },
    )

    create_table_in_dw_staging >> create_table_in_dw >> load_dw_table_into_redshift

    return sub_dag


def build_subdags(layer):
    # create subdag for each table
    file_list = FileService.list_files(f"{QUERIES_BIGFONE_EVENT_DATALAKE_PATH}/{layer}")
    subdags = {}

    for file_name in file_list:
        file_name = FileService.remove_file_extension(file_name)
        slugged_table_name = file_name.replace("_", "-")
        table_sub_dag = BaseSubDAG.get_sub_dag_operator(
            dag=dag,
            sub_dag_name=f"load-{slugged_table_name}-to-{layer}",
            sub_dag_func=eval(f"{layer}_tasks"),
            table_name=file_name,
            slugged_table_name=slugged_table_name,
        )
        subdags[file_name] = table_sub_dag

    # subdags is a dict where the keys are table or file names
    # and the values are corresponding subdag objects
    return subdags


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
            "parameters": ["{{ ds }}", ENV, DATALAKE_BUCKET],
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
            "parameters": ["{{ ds }}", ENV, DATALAKE_BUCKET],
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
            "parameters": [
                "{{ ds }}",
                ENV,
                DATALAKE_BUCKET,
                ATHENA_QUERY_RESULT_LOCATION,
            ],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

enrich_sub_dags = build_subdags("enrich")
dw_sub_dags = build_subdags("dw")

airflow_helpers.chain(
    create_cluster_task,
    load_event_table_to_raw_task,
    load_event_table_to_clean_task,
    create_clean_partition_task,
)
create_clean_partition_task >> list(enrich_sub_dags.values())

# fact_call_ura_paths dependency
[enrich_sub_dags.pop("call_ura_events")] >> dw_sub_dags["fact_call_ura_paths"]
[
    enrich_sub_dags.pop("call_context_data"),
    enrich_sub_dags.pop("call_recording_available_events"),
    enrich_sub_dags.pop("dialed_phone"),
] >> dw_sub_dags["dim_call"]

list(enrich_sub_dags.values()) >> terminate_cluster_task
list(dw_sub_dags.values()) >> terminate_cluster_task
