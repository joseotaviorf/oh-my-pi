import os
import re
from datetime import datetime
from pendulum import timezone
from functools import reduce

from airflow.models import DAG
from airflow.utils.helpers import cross_downstream
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

# Pipeline inputs
SOURCE = "olos_dialer"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2023, 1, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "30 1 * * *"
CLUSTER_DESCRIPTION = "databricks_12_2_med_general_cluster"

config_service = ConfigurationService(SOURCE)
PARTITION_COLS = config_service.get_config("partition_cols")
TABLES_LIST = config_service.get_config("tables_list")
LIST_OUT_OF_PATTERN = config_service.get_config("list_out_of_pattern")

athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
raw_spark_job_file = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/load_{SOURCE}_raw.py"
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


def get_date_param(dag_run, ds, date_param_name):
    date_param = dag_run.conf.get(date_param_name) if dag_run.conf else None
    if date_param and re.match(r"[0-9]{4}\-[0-9]{2}\-[0-9]{2}", date_param):
        return date_param
    return ds

def change_case(table_name, list_out_of_pattern=LIST_OUT_OF_PATTERN):
    for table_dict in list_out_of_pattern:
      if table_name in table_dict:
        return table_dict[table_name]
    table_name = table_name.replace('_', '')
    return reduce(lambda x, y: x + ('_' if y.isupper() else '') + y, table_name).lower()

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
    user_defined_macros={
        "get_date_param": get_date_param,
        "change_case": change_case
    },
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

datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=SOURCE,
    spark_jobs_path=base_spark_jobs_path,
    athena_query_result_location=athena_query_results_bucket,
)

for table_name in TABLES_LIST:

    raw_task_group = datalake_task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        extraction_spark_job_file=raw_spark_job_file,
        raw_spark_job_extra_args=[
            SOURCE,
            "{{ get_date_param(dag_run, ds, 'load_start_date') }}",
            "{{ get_date_param(dag_run, ds, 'load_end_date') }}",
            table_name,
        ],
        has_hive_sync=False,
    )

    clean_task_group = datalake_task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=change_case(table_name),
        is_incremental=True,
        has_create_external_table_task=False,
        partitions=PARTITION_COLS,
        extra_query_template_params={
            "load_start_date": "{{ get_date_param(dag_run, ds, 'load_start_date') }}",
            "load_end_date": "{{ get_date_param(dag_run, ds, 'load_end_date') }}",
        },
    )

    create_cluster_task.set_downstream(DatalakeTaskGroup.first_tasks(raw_task_group))

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))

    # adding data quality tasks
    independent_tasks = DatalakeTaskGroup.independent_tasks(clean_task_group)

    if independent_tasks:
        terminate_cluster_task.set_upstream(independent_tasks)
