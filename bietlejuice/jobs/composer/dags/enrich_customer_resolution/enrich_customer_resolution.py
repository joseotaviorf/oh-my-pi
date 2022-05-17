import os
from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from airflow.utils.helpers import chain

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseTaskGroup, DAGOwnerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.base.airflow.helpers.task_flow_helper import (
    TaskFlowHelper,
)
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2021, 11, 16, 0, 0, 0, tzinfo=LOCAL_TZ)
PARTITION_COLS = ["year", "month", "day"]

CONTEXT = "customer_resolution"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(DAG_NAME)
athena_query_result_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_9_1_med_general_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["spark_env_vars"]["ENVIRONMENT"] = ENV

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_SS,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
    athena_query_result_location=athena_query_result_bucket,
)

enrich_task_groups = {}
tables = config_service.get_config("tables")
inner_dependencies = config_service.get_config("inner_dependencies")

for table, configs in tables.items():
    partitions = configs.get("partition_cols")
    is_incremental = configs.get("is_incremental")
    enrich_task_groups[table] = datalake_task_group.build_enrich_task_group(
        table_name=table,
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        is_incremental=is_incremental,
        partitions=partitions,
    )

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = datalake_task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=enrich_task_groups,
    dag_inner_dependencies=inner_dependencies,
)

chain(
    create_cluster_task,
    BaseTaskGroup.all_first_tasks(task_groups_boundaries_without_inner_dependencies)
    + BaseTaskGroup.first_tasks(inner_dependencies_task_groups_boundaries),
)

chain(
    BaseTaskGroup.all_last_tasks(task_groups_boundaries_without_inner_dependencies)
    + BaseTaskGroup.last_tasks(inner_dependencies_task_groups_boundaries),
    terminate_cluster_task,
)
