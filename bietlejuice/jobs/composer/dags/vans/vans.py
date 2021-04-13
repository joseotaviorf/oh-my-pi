from datetime import datetime
import pendulum

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.dags.vans import (
    SOURCE,
    QUERIES_VANS_DATALAKE_PATH,
    DW_SCHEMA,
)
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG
from bietlejuice.jobs.composer.services import FileService

DAG_ID = f"bietlejuice.{SOURCE}"

ENV = Variable.get("environment")
DW_BUCKET = Variable.get("dw_bucket")

DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), SOURCE
)

CLUSTER_DESCRIPTION = Variable.get("databricks_bietlejuice_vans", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH


DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {
        "jar": f"{ARTIFACTS_S3_BUCKET}/mysql-connector-java/mysql-connector-java-5.1.47.jar"
    }
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

# bietlejuice paths
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
BASE_SPARK_JOB_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"

# dag params
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 10, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
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
        task_id="sync-hive-metastore-clean-tables",
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

    validate_sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id="validate-sync-hive-metastore-clean-table",
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOB_PATH
                + "validate_sync_metastore_tables.py",
                "parameters": [
                    LayerEnum.CLEAN.value,
                    SOURCE,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    load_clean_table_task >> create_external_table_task

    load_clean_table_task >> sync_metastore_table_task >> validate_sync_metastore_table_task

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

    sync_metastore_dw_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="sync-hive-metastore-dw-tables",
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

    validate_sync_metastore_dw_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=sub_dag,
        task_id="validate-sync-hive-metastore-dw-table",
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOB_PATH
                + "validate_sync_metastore_tables.py",
                "parameters": [
                    LayerEnum.DW.value,
                    DW_SCHEMA,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    create_table_in_dw_staging >> create_table_in_dw >> load_dw_table_into_redshift

    airflow_helpers.chain(
        create_table_in_dw,
        sync_metastore_dw_tables_task,
        validate_sync_metastore_dw_table_task,
    )

    return sub_dag


def build_subdags(stage):
    # create subdag for each table
    file_list = FileService.list_files(f"{QUERIES_VANS_DATALAKE_PATH}/{stage}")
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

vans_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="vans-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "load_vans_into_datalake.py",
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

validate_sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id="validate-sync-hive-metastore-table",
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOB_PATH + "validate_sync_metastore_tables.py",
            "parameters": [LayerEnum.RAW.value, SOURCE, "--all-tables"],
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
    vans_to_datalake_raw_task,
    sync_metastore_tables_task,
    validate_sync_metastore_table_task,
    terminate_cluster_task,
)

vans_to_datalake_raw_task >> list(clean_sub_dags.values())

# fact_banking_file_payment dependencies
[
    clean_sub_dags["boleto"],
    clean_sub_dags["payment"],
    clean_sub_dags["payment_boleto"],
] >> dw_sub_dags["fact_banking_file_payments"]

# dim_occurrence_code dependencies
[
    clean_sub_dags["boleto"],
    clean_sub_dags["payment"],
    clean_sub_dags["payment_boleto"],
] >> dw_sub_dags["dim_occurrence_code"]

# dim_banking_file_payment dependencies
[
    clean_sub_dags.pop("boleto"),
    clean_sub_dags.pop("payment"),
    clean_sub_dags.pop("payment_boleto"),
    clean_sub_dags.pop("bank_boleto"),
    clean_sub_dags.pop("bank"),
    clean_sub_dags.pop("bank_payment"),
] >> dw_sub_dags["dim_banking_file_payment"]

# look out! the clean sub dags no longer have the dependency instances
list(clean_sub_dags.values()) >> terminate_cluster_task
list(dw_sub_dags.values()) >> terminate_cluster_task
