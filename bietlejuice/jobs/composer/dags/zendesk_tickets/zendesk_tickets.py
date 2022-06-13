from datetime import datetime
import pendulum
import os

from airflow.utils.helpers import chain, cross_downstream
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.base.databricks import (
    DatabricksGroupNameEnum,
    ClusterPermissionEnum,
)
from bietlejuice.jobs.composer.services import ConfigurationService


SOURCE = "zendesk_tickets"
CONTEXT = SOURCE
config_service = ConfigurationService(SOURCE)


# default configs
ENV = os.environ.get("ENVIRONMENT")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
artifacts_bucket = config_service.get_config("artifacts_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
default_libraries = config_service.get_config("default_libraries")

# s3 paths setup
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
raw_spark_job_path = s3_prefix + f"/spark_jobs/{SOURCE}/add_partitions_to_raw_tables.py"
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"

# databricks var
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_zendesk_tickets", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{spark_jobs_logs_path}{SOURCE}"
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

# dag vars
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 9, 9, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"

local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_SS,
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
    cluster_configuration=CLUSTER_DESCRIPTION,
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

raw_task_groups = task_group.build_raw_task_group_for_all_tables(
    source=SOURCE,
    target_database_base_name=SOURCE,
    extraction_spark_job_file=raw_spark_job_path,
    raw_spark_job_extra_args=["{{ ds }}"],
)

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
)

chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_groups))

cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_groups),
    DatalakeTaskGroup.all_first_tasks(clean_task_groups),
)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
