from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_sub_dag import DatalakeSubDAG
from bietlejuice.jobs.composer.services import FileService

# ENV setup
ENV = Variable.get("environment")

# DAG params setup
SOURCE = "firestore"
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")
MAIN_START_DATE = datetime(2020, 8, 29, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "30 0 * * *"

# s3 paths setup
DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
DATABRICKS_BUCKET = Variable.get("databricks_s3_bucket")
LOGS_OUTPUT_PATH = f"s3://{DATABRICKS_BUCKET}/logs/jobs/{SOURCE}"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}/"
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")

# cluster setup
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

PUBSUB_CREDENTIALS_PATH = Variable.get("pubsub_credentials_path")
CLUSTER_DESCRIPTION["spark_env_vars"][
    "GOOGLE_APPLICATION_CREDENTIALS"
] = PUBSUB_CREDENTIALS_PATH

# job params
PROJECT_ID = Variable.get("pwa_google_project_id")
SUBSCRIPTIONS = [
    {
        "subscription_id": "domainSaleOffer-audit-data-engineering-subscription",
        "table_name": "sale_offer",
    },
    {
        "subscription_id": "mondayBoard-audit-data-engineering-subscription",
        "table_name": "monday",
    },
    {
        "subscription_id": "offers-audit-data-engineering-subscription",
        "table_name": "rent_offer",
    },
]


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

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

clean_sub_dag = DatalakeSubDAG(
    dag_id=DAG_ID,
    start_date=MAIN_START_DATE,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    layer=LayerEnum.CLEAN,
    database_base_name=SOURCE,
    relative_query_path=SOURCE,
    spark_job_paths=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

file_list = FileService.list_sql_files_without_extension_from_layer(
    SOURCE, LayerEnum.CLEAN.value
)
clean_sub_dags = clean_sub_dag.build_subdags_from_sql_files(
    dag, file_list, is_incremental=True, partitions=["year", "month", "day"]
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

# Creating sub dags
for subscription in SUBSCRIPTIONS:

    slugged_table_name = subscription["table_name"].replace("_", "-")

    load_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{slugged_table_name}-into-raw",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "load_firestore_into_raw.py",
                "parameters": [
                    ENV,
                    SOURCE,
                    DATALAKE_BUCKET,
                    PROJECT_ID,
                    PUBSUB_CREDENTIALS_PATH,
                    subscription["subscription_id"],
                    subscription["table_name"],
                ],
            }
        },
    )

    create_cluster_task >> load_to_raw_task >> clean_sub_dags.pop(
        subscription["table_name"]
    ) >> terminate_cluster_task
