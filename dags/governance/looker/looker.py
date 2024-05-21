import os
import pendulum
from datetime import datetime

from airflow.utils.helpers import chain
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService

SOURCE = "looker"
CONTEXT = SOURCE
DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
ENV = os.environ.get("ENVIRONMENT")
MAIN_START_DATE = datetime(2021, 8, 10, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 5 * * *"

config_service = ConfigurationService(SOURCE)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
RAW_SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/"

CLUSTER_DESCRIPTION = config_service.get_config(
    f"databricks_10_4_min_general_photon_cluster"
)

EXECUTION_DATE = "{{ ds }}"

default_libraries = config_service.get_config("default_libraries")
cluster_libs = config_service.get_config("cluster_libs")
all_libs = default_libraries + cluster_libs


extra_env_vars = config_service.get_config("extra_env_vars")
for key, val in extra_env_vars.items():
    CLUSTER_DESCRIPTION["spark_env_vars"][key] = val

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GOVERNANCE,
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
    libraries=all_libs,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=SOURCE,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)

tables = config_service.get_config("tables")
partition_cols = config_service.get_config("partition_cols")

raw_task_groups = {}
for table in tables:
    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        table_name=table,
        target_database_base_name=SOURCE,
        extraction_spark_job_file=f"{RAW_SPARK_JOB_PATH}load_{table}_to_raw.py",
        raw_spark_job_extra_args=[SOURCE, table, EXECUTION_DATE],
    )
    raw_task_groups[table] = raw_task_group

clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    is_incremental=True,
    partitions=partition_cols,
    execution_date=EXECUTION_DATE,
)

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(raw_task_groups))

TaskFlowHelper.chain_task_groups_via_common_table(raw_task_groups, clean_task_groups)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
