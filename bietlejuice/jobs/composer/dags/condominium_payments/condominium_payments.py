from datetime import datetime
import os
import pendulum

from airflow.utils.helpers import chain, cross_downstream
from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)
from bietlejuice.jobs.composer.base.databricks import (
    DatabricksGroupNameEnum,
    ClusterPermissionEnum,
)

SOURCE = "condominium_payments"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"

# dag vars
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2022, 4, 7, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(dag_name=SOURCE, env=ENV)

# default configs
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
default_libraries = config_service.get_config("default_libraries")

# s3 paths setup
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
raw_spark_job_path = (
    s3_prefix + f"/spark_jobs/{SOURCE}/load_condominium_payments_into_datalake.py"
)
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"

tables_list = config_service.get_config("tables_list")

# databricks var
cluster_description = config_service.get_config("databricks_10_4_min_memory_cluster")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

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
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries,
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

for table_name in tables_list:

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        extraction_spark_job_file=raw_spark_job_path,
        raw_spark_job_extra_args=[SOURCE, table_name],
    )

    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
    )

    chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_group))

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
