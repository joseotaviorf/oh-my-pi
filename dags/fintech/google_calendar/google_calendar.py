import os
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from airflow.operators.python_operator import ShortCircuitOperator
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import cross_downstream

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_builders.main_builder.short_circuit_functions.dag_run_date_validators import DAGRunDateValidators
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService

# Pipeline Inputs
SOURCE = "google_calendar"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2023, 4, 3, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 12 * * *"
CLUSTER_DESCRIPTION = "databricks_10_4_min_general_cluster"

config_service = ConfigurationService(dag_name=SOURCE)
datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"
raw_spark_job_path = f"{s3_prefix}/spark_jobs/{SOURCE}/load_{CONTEXT}.py"

default_libraries = config_service.get_config("default_libraries")
cluster_description = config_service.get_config(CLUSTER_DESCRIPTION)

dag_documentation = config_service.get_config("dag_documentation")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
ENV = os.environ.get("ENVIRONMENT")
DAG_OWNER = DAGOwnerEnum.DATA_FINTECH

extra_libs = [
    {"pypi": {"package": "google-api-python-client==2.48.0"}},
    {"pypi": {"package": "oauth2client==4.1.3"}},
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=SOURCE,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=dag_documentation,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        dag_owner=DAG_OWNER,
    ),
)
skip_run_task = ShortCircuitOperator(
    task_id=f"check-day-to-skip-execution",
    python_callable=DAGRunDateValidators.check_is_specific_day_of_month,
    op_args=["{{ macros.ds_add(ds, 1) }}", 1],
)
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries + extra_libs,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=CONTEXT,
    spark_jobs_path=base_spark_jobs_path,
    athena_query_result_location=athena_query_results_bucket,
)

tables = config_service.get_config("tables")
partition_columns = config_service.get_config("partition_columns")

for table in tables:
    table_name = table["table_name"]
    extraction_type = table["extraction_type"]
    calendar_region = table["calendar_region"]
    parameters = [SOURCE, table_name, calendar_region]

    is_incremental = extraction_type == "incremental"

    if is_incremental:
        parameters.append(str(partition_columns))

    partitions = partition_columns if is_incremental else None

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        extraction_spark_job_file=raw_spark_job_path,
        raw_spark_job_extra_args=parameters,
    )

    create_cluster_task.set_downstream(DatalakeTaskGroup.first_tasks(raw_task_group))

    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        is_incremental=False,
    )

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))

skip_run_task.set_downstream(create_cluster_task)
