from datetime import datetime
import pendulum

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.dags.dw_teravoz_fact_calls import (
    SOURCE,
    DW_SCHEMA,
    QUERIES_DW_TERAVOZ_FACT_CALLS_PATH,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG
from bietlejuice.jobs.composer.services import FileService

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 2, 20, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 5 * * *"

DAG_ID = f"bietlejuice.{SOURCE}"
ENV = Variable.get("environment")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")
DW_BUCKET = Variable.get("dw_bucket")
DATALAKE_OLD_BUCKET = Variable.get("datalake_old_bucket")
ZENDESK_TICKETS_CUSTOM_FIELDS_S3_PATH = (
    f"s3://{DATALAKE_OLD_BUCKET}/clean/zendesk/custom_fields"
)

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), SOURCE
)

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_memory_optimized_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

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
)


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

    create_table_in_dw_staging >> create_table_in_dw >> load_dw_table_into_redshift

    return sub_dag


def build_subdags(stage):
    # create subdag for each table
    file_list = FileService.list_files(f"{QUERIES_DW_TERAVOZ_FACT_CALLS_PATH}/{stage}")
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

zendesk_tickets_custom_fields_to_metastore_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="zendesk-tickets-custom-fields-to-metastore",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH
            + "load_zendesk_tickets_custom_fields_into_metastore.py",
            "parameters": [
                "{{ ds }}",
                "datalake_clean",
                "zendesk_custom_fields",
                "dt_extracted",
                ZENDESK_TICKETS_CUSTOM_FIELDS_S3_PATH,
                "parquet",
                '{"spark.sql.parquet.binaryAsString": "true"}',
            ],
        }
    },
)

dw_sub_dags = build_subdags("dw")

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> zendesk_tickets_custom_fields_to_metastore_task >> list(
    dw_sub_dags.values()
) >> terminate_cluster_task
