from datetime import datetime
import pendulum
import os

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.dags.retsuko import (
    SOURCE,
    DW_SCHEMA,
    QUERIES_RETSUKO_DATALAKE_PATH,
)
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG
from bietlejuice.jobs.composer.services import FileService

DAG_ID = f"bietlejuice.{SOURCE}"
ENV = os.environ.get("ENVIRONMENT")
DW_BUCKET = Variable.get("dw_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), SOURCE
)

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_retsuko", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 1, 25, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 8 * * *"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID),
)


def clean_tasks(sub_dag_name, table_name, slugged_table_name):

    sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    load_clean_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"create-clean-{slugged_table_name}-in-data-lake",
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_clean_table_in_datalake.py",
                "parameters": [table_name, ENV, DATALAKE_BUCKET],
            }
        },
    )

    create_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"create-clean-external-{slugged_table_name}-table",
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_clean_external_table.py",
                "parameters": [
                    table_name,
                    ENV,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                ],
            }
        },
    )

    sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="sync-hive-metastore-clean-table",
        dag=sub_dag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOB_PATH + "sync_metastore_tables.py",
                "parameters": [
                    DATALAKE_BUCKET,
                    LayerEnum.CLEAN.value,
                    SOURCE,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    load_clean_table_task.set_downstream(
        [create_external_table_task, sync_metastore_table_task]
    )

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
                "python_file": SPARK_JOBS_PATH + "create_table_in_dw_staging.py",
                "parameters": [DW_BUCKET, table_name, ENV],
            }
        },
    )

    create_table_in_dw = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"load-{slugged_table_name}-into-dw-{DW_SCHEMA}",
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_table_in_dw.py",
                "parameters": [DW_BUCKET, table_name, ENV],
            }
        },
    )

    load_dw_table_into_redshift = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id=f"load-{slugged_table_name}-into-redshift",
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "load_dw_table_into_redshift.py",
                "parameters": [DW_BUCKET, table_name, ENV, SPECTRUM_IAM_ROLE],
            }
        },
    )

    sync_metastore_dw_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="sync-hive-metastore-dw-table",
        dag=sub_dag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOB_PATH + "sync_metastore_tables.py",
                "parameters": [
                    DW_BUCKET,
                    LayerEnum.DW.value,
                    DW_SCHEMA,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    airflow_helpers.chain(
        create_table_in_dw_staging,
        create_table_in_dw,
        [load_dw_table_into_redshift, sync_metastore_dw_table_task],
    )

    return sub_dag


def build_subdags(stage):
    # create subdag for each table
    file_list = FileService.list_files(f"{QUERIES_RETSUKO_DATALAKE_PATH}/{stage}")
    subdags = {}

    for file_name in file_list:
        file_name = FileService.remove_file_extension(file_name)
        slugged_table_name = file_name.replace("_", "-")
        table_sub_dag = BaseSubDAG.get_sub_dag_operator(
            dag=dag,
            sub_dag_name=f"load-{slugged_table_name}-to-{stage}",
            sub_dag_func=eval(f"{stage}_tasks"),
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

retsuko_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="retsuko-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "load_retsuko_into_datalake.py",
            "parameters": [ENV, DATALAKE_BUCKET],
        }
    },
)

sync_metastore_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-raw-tables",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOB_PATH + "sync_metastore_tables.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.RAW.value,
                SOURCE,
                "--all-tables",
            ],
        }
    },
)

clean_sub_dags = build_subdags("clean")
dw_sub_dags = build_subdags("dw")

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

airflow_helpers.chain(
    create_cluster_task,
    retsuko_to_datalake_raw_task,
    sync_metastore_tables_task,
    terminate_cluster_task,
)

retsuko_to_datalake_raw_task >> list(clean_sub_dags.values())

# remove the dict the element {"invoice": invoice instance sub dag} and return the value
# because we don't want to connect that subdag with the terminate_cluster task
clean_sub_dags.pop("invoice") >> dw_sub_dags["dim_invoice"]
# the same for the account and entry sub dags
[clean_sub_dags.pop("account"), clean_sub_dags.pop("entry")] >> dw_sub_dags[
    "dim_invoice_entry"
]

# look out! the clean sub dags no longer have the dependency instances
list(clean_sub_dags.values()) >> terminate_cluster_task
list(dw_sub_dags.values()) >> terminate_cluster_task
