import pendulum

from datetime import datetime
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.services import ConfigurationService

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 12, 2, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 9 * * *"

DW_SCHEMA = "metrics"
CONTEXT = "shared_metrics"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"


configs_service = ConfigurationService(DAG_NAME)
dw_bucket = configs_service.get_config("dw_bucket")
doc_md_chart_url = configs_service.get_config("doc_md_chart_url")
databricks_bietlejuice_repo_path = configs_service.get_config(
    "databricks_bietlejuice_repo_path"
)
metrics_path = configs_service.get_config("metrics_path")
spark_jobs_logs_path = configs_service.get_config("spark_jobs_logs_path")

spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base"
logs_output_path = "{}{}".format(spark_jobs_logs_path, DAG_ID)

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = logs_output_path

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
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

ctas_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id="create-table-as-select",
    json={
        "spark_python_task": {
            "python_file": f"{spark_jobs_path}/create_metrics_tables.py",
            "parameters": [DW_SCHEMA, DatabaseEnum.DW, metrics_path],
        }
    },
)


terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> ctas_task >> terminate_cluster_task
