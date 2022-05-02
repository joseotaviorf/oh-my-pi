from datetime import datetime
import pendulum
import os

from airflow.utils.helpers import chain
from airflow.models import DAG, Variable
from airflow.operators.python_operator import ShortCircuitOperator
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)


def check_valid_run_date(dag_execution_date, crawler_weekday):
    return (
        datetime.strptime(dag_execution_date, "%Y-%m-%d").weekday() == crawler_weekday
    )


LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2021, 7, 20, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 6 * * 2,3,5"
CONTEXT = "crawlers_listings"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
PARTITION_COLS = ["address_city", "year", "month", "day"]
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(DAG_NAME)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
crawlers = config_service.get_config("tables")
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["spark_env_vars"]["ENVIRONMENT"] = ENV
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{spark_jobs_logs_path}{DAG_ID}"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
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

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)

for crawler in crawlers:
    crawler_name = crawler["table_name"]
    crawler_weekday = crawler["weekday_run"]

    task_group = datalake_task_group.build_enrich_task_group(
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        table_name=crawler_name,
        is_incremental=True,
        partitions=PARTITION_COLS,
    )
    skip_run_task = ShortCircuitOperator(
        task_id=f"check-day-to-skip-execution-{crawler_name}",
        python_callable=check_valid_run_date,
        op_kwargs={"dag_execution_date": "{{ds}}", "crawler_weekday": crawler_weekday},
    )

    chain(create_cluster_task, skip_run_task, DatalakeTaskGroup.first_tasks(task_group))
    chain(DatalakeTaskGroup.last_tasks(task_group), terminate_cluster_task)
