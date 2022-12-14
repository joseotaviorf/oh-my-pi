import os
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from airflow.utils.helpers import cross_downstream
from airflow.contrib.operators.awsbatch_operator import AWSBatchOperator
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum


# Pipeline inputs
SOURCE = "casa_mineira_lifull_campaigns"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2021, 8, 26, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 2 * * *"
CLUSTER_DESCRIPTION = "databricks_10_4_min_general_cluster"

config_service = ConfigurationService(SOURCE)
accounts = config_service.get_config("accounts")
raw_table_name = config_service.get_config("raw_table_name")
aws_conn_id = config_service.get_config("aws_conn_id")
raw_output_path = config_service.get_config("raw_output_path")
clean_tables_list = config_service.get_config("clean_tables_list")
partition_cols = config_service.get_config("partition_cols")

athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
raw_spark_job_file = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/create_{SOURCE}_raw.py"
)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
ENV = os.environ.get("ENVIRONMENT")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
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
    spark_jobs_path=base_spark_jobs_path,
    athena_query_result_location=athena_query_results_bucket,
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

raw_task_group = task_group.build_raw_task_group_for_single_table(
    source=SOURCE,
    target_database_base_name=SOURCE,
    table_name="campaigns_overview_report",
    extraction_spark_job_file=raw_spark_job_file,
    raw_spark_job_extra_args=[SOURCE],
)

create_cluster_task.set_downstream(DatalakeTaskGroup.first_tasks(raw_task_group))

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
        aws_conn_id=aws_conn_id,
        region_name="us-east-1",
    )

    aws_batch_start_job_task.set_downstream(create_cluster_task)

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
