import os
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

# Pipeline inputs
CONTEXT = "marketing_costs_sharing_rules"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2019, 1, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None
CLUSTER_DESCRIPTION = "custom_cluster"

config_service = ConfigurationService(DAG_NAME)
MAIN_TABLE = config_service.get_config("main_table")

datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")
cluster_configuration["data_security_mode"] = "SINGLE_USER"
cluster_configuration["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
cluster_configuration["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = "quintoandar_{{ var.value.environment }}"
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

ENV = os.environ.get("ENVIRONMENT")

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
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(databricks_conn_id="databricks_new", dag=dag, task_id="terminate-cluster"
)

datalake_task_group = DatalakeTaskGroup(databricks_conn_id="databricks_new", dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
)

table_names = datalake_task_group._get_table_names_from_sql_files(
    layer=LayerEnum.ENRICH
)

enrich_task_groups = {}
for table_name in table_names:
    extra_query_template_params = (
        {"id_rule": table_name} if table_name != MAIN_TABLE else None
    )
    enrich_task_groups[table_name] = datalake_task_group.build_enrich_task_group(
        table_name=table_name,
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        extra_query_template_params=extra_query_template_params,
        has_create_external_table_task=False,
    )

inner_dependencies = {
    MAIN_TABLE: list(set(enrich_task_groups.keys()).difference(set([MAIN_TABLE])))
}

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
