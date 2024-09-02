import os
from datetime import datetime

from airflow.models import DAG
from airflow.utils.helpers import chain
from airflow.operators.python_operator import ShortCircuitOperator
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from pendulum import timezone

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_builders.main_builder.short_circuit_functions.dag_run_date_validators import (
    DAGRunDateValidators,
)
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.reverse_task_group import ReverseTaskGroup
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.services.configuration_service import ConfigurationService


ENV = os.environ.get("ENVIRONMENT")
SOURCE = "tiers"
DAG_NAME = f"reverse_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2024, 8, 23, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None
DAG_OWNER = DAGOwnerEnum.DATA_AGENTS

config_service = ConfigurationService(DAG_NAME)
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
s3_bucket = config_service.get_config("datalake_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"

cluster_description = config_service.get_config(
    "databricks_12_2_med_general_photon_cluster"
)
default_libraries = config_service.get_config("default_libraries")
partition_cols = config_service.get_config("partition_cols")
dag_documentation = config_service.get_config("dag_documentation")
range_of_days_to_run = config_service.get_config("range_of_days_to_run")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
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
        dag_name=DAG_NAME,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=dag_documentation,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        dag_owner=DAG_OWNER,
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries,
)

skip_run_task = ShortCircuitOperator(
    task_id=f"check-day-to-skip-execution",
    python_callable=DAGRunDateValidators.check_is_in_range_of_days,
    op_args=["{{ macros.ds_add(ds, 1) }}", range_of_days_to_run],
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = ReverseTaskGroup(
    dag=dag,
    env=ENV,
    s3_bucket=s3_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
)

datalake_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.REVERSE,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    is_incremental=True,
    partitions=partition_cols,
)

chain(
    skip_run_task,
    create_cluster_task,
    ReverseTaskGroup.all_first_tasks(datalake_task_groups),
)
chain(ReverseTaskGroup.all_last_tasks(datalake_task_groups), terminate_cluster_task)
