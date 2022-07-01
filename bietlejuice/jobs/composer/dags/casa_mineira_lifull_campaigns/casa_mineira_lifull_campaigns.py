from datetime import datetime
from pendulum import timezone
import os
from airflow.contrib.operators.awsbatch_operator import AWSBatchOperator


from airflow.utils.helpers import chain, cross_downstream
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

SOURCE = "casa_mineira_lifull_campaigns"
DAG_ID = f"bietlejuice.{SOURCE}"
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(SOURCE)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

accounts = config_service.get_config("accounts")
raw_table_name = config_service.get_config("raw_table_name")
raw_output_path = config_service.get_config("raw_output_path")
clean_tables_list = config_service.get_config("clean_tables_list")
partition_cols = config_service.get_config("partition_cols")

MAIN_START_DATE = datetime(2021, 8, 26, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 2 * * *"
BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
RAW_SPARK_JOB_FILE = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/create_{SOURCE}_raw.py"
)

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["spark_env_vars"]["ENVIRONMENT"] = ENV
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{spark_jobs_logs_path}{DAG_ID}"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    catchup=False,
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=SOURCE,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

raw_task_group = task_group.build_raw_task_group_for_single_table(
    source=SOURCE,
    target_database_base_name=SOURCE,
    table_name="campaigns_overview_report",
    extraction_spark_job_file=RAW_SPARK_JOB_FILE,
    raw_spark_job_extra_args=[SOURCE],
)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

for account_type, account_info in accounts.items():
    account_id = account_info["account_id"]
    account_name = account_info["account_name"]
    output_path = raw_output_path.format(
        datalake_bucket=datalake_bucket,
        source=SOURCE,
        raw_table_name=raw_table_name,
        account_id=account_id,
        execution_date="{{ ds }}",
    )

    aws_batch_start_job_task = AWSBatchOperator(
        dag=dag,
        task_id=f"load-{account_type}-lifull-campaigns-report",
        job_name="crawler-lifull-{}-{}".format(account_type, "{{ ds }}"),
        job_definition="5a-data-crawler-lifull",
        job_queue="5a-data-crawler-mkt-queue",
        parameters={
            "start_date": "start_date={{ ds }}",
            "end_date": "end_date={{ ds }}",
            "account_id": f"account_id={account_id}",
            "account_name": f"account_name={account_name}",
            "output_path": output_path,
        },
        overrides={},
        aws_conn_id="aws_prod_data",
        region_name="us-east-1",
    )

    chain(aws_batch_start_job_task, create_cluster_task)

for clean_table_name in clean_tables_list:
    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=clean_table_name,
        is_incremental=True,
        partitions=partition_cols,
        has_create_external_table_task=False,
    )

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
