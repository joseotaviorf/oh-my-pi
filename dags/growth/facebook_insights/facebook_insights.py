from datetime import datetime
from pendulum import timezone
import os
import re

from airflow.utils.helpers import chain, cross_downstream
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

SOURCE = "facebook_insights"
DAG_ID = f"bietlejuice.{SOURCE}"
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(SOURCE)
ATHENA_QUERY_RESULTS_BUCKET = config_service.get_config("athena_query_results_bucket")
DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
DATABRICKS_BIETLEJUICE_REPO_PATH = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
DOC_MD_CHART_URL = config_service.get_config("doc_md_chart_url")
artifacts_bucket = config_service.get_config("artifacts_bucket")

PARTITION_COLS = config_service.get_config("partition_cols")
TABLES_LIST = config_service.get_config("tables_list")

MAIN_START_DATE = datetime(2019, 6, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 3 * * *"
RAW_SPARK_JOB_FILE = f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/{SOURCE}/load_facebook_insights_raw.py"
BASE_SPARK_JOBS_PATH = f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/base/"

# cluster setup
CLUSTER_DESCRIPTION = "databricks_10_4_min_io-general_cluster"
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")

CUSTOM_LIBRARIES = [
    {
        "whl": f"{artifacts_bucket}/facebook-api-client-python/"
        f"quintoandar_facebook_api_client-0.1.2-py2.py3-none-any.whl"
    }
]

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]


def get_date_param(dag_run, ds, date_param_name):
    date_param = dag_run.conf.get(date_param_name) if dag_run.conf else None
    if date_param and re.match(r"[0-9]{4}\-[0-9]{2}\-[0-9]{2}", date_param):
        return date_param
    return ds


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
        chart_url=DOC_MD_CHART_URL, dag_id=DAG_ID
    ),
    user_defined_macros={"get_date_param": get_date_param},
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries + CUSTOM_LIBRARIES,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    relative_query_path=SOURCE,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULTS_BUCKET,
)

for table_name in TABLES_LIST:
    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        extraction_spark_job_file=RAW_SPARK_JOB_FILE,
        raw_spark_job_extra_args=[
            SOURCE,
            table_name,
            "{{ get_date_param(dag_run, ds, 'load_start_date') }}",
            "{{ get_date_param(dag_run, ds, 'load_end_date') }}",
            "{{ dag_run.conf['accounts'] }}",
        ],
    )

    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        is_incremental=True,
        has_create_external_table_task=False,
        partitions=PARTITION_COLS,
        extra_query_template_params={
            "load_start_date": "{{ get_date_param(dag_run, ds, 'load_start_date') }}",
            "load_end_date": "{{ get_date_param(dag_run, ds, 'load_end_date') }}",
        },
    )

    chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))

    # adding data quality tasks
    independent_tasks = DatalakeTaskGroup.independent_tasks(clean_task_group)

    if independent_tasks:
        terminate_cluster_task.set_upstream(independent_tasks)
