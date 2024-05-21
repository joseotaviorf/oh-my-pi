import os
import re
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from airflow.utils.helpers import chain
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

# Pipeline inputs
CONTEXT = "consolidated_marketing_metrics"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2019, 1, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None

CLUSTER_DESCRIPTION = "custom_cluster"
config_service = ConfigurationService(DAG_NAME)
partition_cols = config_service.get_config("partition_cols")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
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


dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
    user_defined_macros={"get_date_param": get_date_param},
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
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
)

enrich_task_groups = datalake_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.ENRICH,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
    is_incremental=True,
    has_create_external_table_task=False,
    partitions=partition_cols,
    execution_date="",
    extra_query_template_params={
        "load_start_date": "{{ get_date_param(dag_run, macros.ds_add(ds, -6), 'load_start_date') }}",
        "load_end_date": "{{ get_date_param(dag_run, ds, 'load_end_date') }}",
    },
)

INNER_DEPENDENCIES = {
    "consolidated_media_metrics": list(
        set(enrich_task_groups.keys()).difference(set(["consolidated_media_metrics"]))
    )
}

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = datalake_task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=enrich_task_groups,
    dag_inner_dependencies=INNER_DEPENDENCIES,
)

chain(
    create_cluster_task,
    datalake_task_group.all_first_tasks(
        task_groups_boundaries_without_inner_dependencies
    )
    + datalake_task_group.first_tasks(inner_dependencies_task_groups_boundaries),
)

chain(
    datalake_task_group.all_last_tasks(
        task_groups_boundaries_without_inner_dependencies
    )
    + datalake_task_group.last_tasks(inner_dependencies_task_groups_boundaries),
    terminate_cluster_task,
)

# Set data quality tasks if exists
independent_tasks = DatalakeTaskGroup.all_independent_tasks(enrich_task_groups)
if independent_tasks:
    terminate_cluster_task.set_upstream(independent_tasks)
