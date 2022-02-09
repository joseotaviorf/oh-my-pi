from datetime import datetime
from bietlejuice.jobs.composer.base.airflow.dag_owner_enum import DAGOwnerEnum
from pendulum import timezone
import os

from airflow.utils.helpers import chain
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

ENV = os.environ.get("ENVIRONMENT")
SOURCE = "tracksale"
DAG_NAME = f"reverse_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2022, 2, 8, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 7 * * *"

config_service = ConfigurationService(DAG_NAME)

artifacts_s3_bucket = config_service.get_config("artifacts_bucket")
datalake_bucket = config_service.get_config("datalake_bucket_reverse")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
REVERSE_SPARK_JOB_PATH = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/reverse_{SOURCE}/"
)

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_tracksale", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{spark_jobs_logs_path}{DAG_ID}"

cluster_libs = config_service.get_config("cluster_libs")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_BEDROCK,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=cluster_libs,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

campaigns = config_service.get_config("campaigns")

for campaign in campaigns:
    campaign_code = campaign["campaign_code"]
    campaign_query = campaign["query"]
    tags = campaign["tags"]

    table_name = campaign_query
    load_campaing_targets_into_datalake = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{table_name}-in-datalake",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": REVERSE_SPARK_JOB_PATH
                + "load_incremental_data_into_datalake_reverse.py",
                "parameters": [ENV, datalake_bucket, SOURCE, table_name],
            }
        },
    )

    load_targets_into_tracksale = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{table_name}-into-tracksale",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": REVERSE_SPARK_JOB_PATH
                + "load_targets_into_tracksale.py",
                "parameters": [
                    ENV,
                    datalake_bucket,
                    SOURCE,
                    campaign_code,
                    table_name,
                    tags,
                    "{{ds}}",
                ],
            }
        },
    )

    chain(
        create_cluster_task,
        load_campaing_targets_into_datalake,
        load_targets_into_tracksale,
        terminate_cluster_task,
    )
