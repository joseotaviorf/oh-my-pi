import pendulum
import os
import json
from datetime import datetime

from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain, cross_downstream

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks.cluster_permission_enum import ClusterPermissionEnum
from bietlejuice.base.databricks.databricks_group_name_enum import (
    DatabricksGroupNameEnum,
)
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService

SOURCE = "kodak"
CONTEXT = SOURCE
config_service = ConfigurationService(SOURCE)
ENV = os.environ.get("ENVIRONMENT")

athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
dag_documentation = config_service.get_config("dag_documentation")
default_libraries = config_service.get_config("default_libraries")
tables = config_service.get_config("tables")
partition_cols = config_service.get_config("partition_cols")

# s3 paths setup
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
raw_spark_job_path = f"{s3_prefix}/spark_jobs/{SOURCE}/load_{SOURCE}_raw.py"
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"

# dag params
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2020, 3, 19, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"

cluster_description = config_service.get_config("custom_cluster")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_REDE,
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
        dag_owner=DAGOwnerEnum.DATA_SS,
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    libraries=default_libraries,
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
    spark_jobs_path=base_spark_jobs_path,
    athena_query_result_location=athena_query_results_bucket,
)

for table_name, table_config in tables.items():
    clean_table_name = table_config.get("clean_table_name", table_name)
    parameters = [SOURCE, table_name]

    extended_parameters = [
        "{{ ds }}",
        table_config["raw_extraction_type"],
        table_config.get("date_filter_column", "updated_at"),
        json.dumps(partition_cols),
    ]

    extended_parameters = list(filter(None, extended_parameters))
    parameters.extend(extended_parameters)

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        table_name=table_name,
        target_database_base_name=CONTEXT,
        extraction_spark_job_file=raw_spark_job_path,
        raw_spark_job_extra_args=parameters,
    )

    is_incremental_clean = table_config["clean_extraction_type"] == "incremental"
    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        table_name=clean_table_name,
        is_incremental=is_incremental_clean,
        partitions=partition_cols if is_incremental_clean else None,
    )

    chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
