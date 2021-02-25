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
from bietlejuice.jobs.composer.dags.enrich_user_phone import (
    DAG_NAME,
    QUERIES_ENRICH_USER_PHONE_DATALAKE_PATH,
)
from bietlejuice.jobs.composer.services import FileService

DAG_ID = f"bietlejuice.{DAG_NAME}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 9, 9, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "30 4 * * *"


ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

# s3 vars
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

# spark_jobs path
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{DAG_NAME}/"

# cluster params
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_enrich_user_phone", deserialize_json=True
)
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
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
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
                "parameters": [ENV, "{{ ds }}", DATALAKE_BUCKET, "enrich", table_name],
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


def build_subdags(layer):
    file_list = FileService.list_files(
        f"{QUERIES_ENRICH_USER_PHONE_DATALAKE_PATH}/{layer}"
    )
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

    return subdags


# ------------------------------ TASKS ------------------------------------------------ #
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

enrich_sub_dags = build_subdags("enrich")

create_cluster_task >> list(enrich_sub_dags.values()) >> terminate_cluster_task
