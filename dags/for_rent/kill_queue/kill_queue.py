from datetime import datetime
import json
import pendulum
import os

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

SOURCE = "kill_queue"
CONTEXT = SOURCE

DAG_ID = f"bietlejuice.{SOURCE}"
ENV = os.environ.get("ENVIRONMENT")
config_service = ConfigurationService(SOURCE)
spectrum_iam_role = config_service.get_config("spectrum_iam_role")
datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_result_location = config_service.get_config("athena_query_results_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
default_libraries = config_service.get_config("default_libraries")

s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
cluster_description = config_service.get_config("databricks_10_4_med_general_cluster")
CUSTOM_LIBRARIES = [
    {"jar": f"{artifacts_bucket}/mysql-connector-java/mysql-connector-java-5.1.47.jar"}
]
LIBRARIES_DESCRIPTION = default_libraries + CUSTOM_LIBRARIES
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

# bietlejuice paths
BASE_SPARK_JOBS_PATH = f"{s3_prefix}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{s3_prefix}/spark_jobs/{SOURCE}/load_{SOURCE}_into_datalake.py"

# dag params
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "30 0 * * *"

config_service = ConfigurationService(SOURCE)

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    libraries=LIBRARIES_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=CONTEXT,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_result_location,
)

tables = config_service.get_config("tables")
partition_cols = config_service.get_config("partition_cols")
for table in tables:
    table_name = table["table_name"]
    extraction_type = table["extraction_type"]
    clean_table_name = table.get("clean_table_name", table_name)
    parameters = [SOURCE, table_name]

    if extraction_type == "incremental":
        extended_parameters = [
            json.dumps(partition_cols),
            table["date_filter_column"],
            "{{ ds }}",
            table.get("unixtime_measure"),
        ]
        extended_parameters = list(filter(None, extended_parameters))
        parameters.extend(extended_parameters)

    raw_spark_job_path = f"{s3_prefix}/spark_jobs/{CONTEXT}/load_{extraction_type}_kill_queue_into_datalake.py"
    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        table_name=table_name,
        target_database_base_name=CONTEXT,
        extraction_spark_job_file=raw_spark_job_path,
        raw_spark_job_extra_args=parameters,
    )

    is_incremental = table.get("extraction_type") == "incremental"
    partitions = partition_cols if is_incremental else None

    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        table_name=clean_table_name,
        is_incremental=is_incremental,
        partitions=partitions,
    )

    chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
