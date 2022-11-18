import os
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.dag_metadata_service import DAGMetadataService
from bietlejuice.base.databricks import ClusterPermissionEnum, DatabricksGroupNameEnum

# Pipeline inputs
CONTEXT = "for_rent"
DW_SCHEMA = f"datamarts_{CONTEXT}"
DAG_NAME = f"dw_datamarts_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2020, 1, 15, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None
CLUSTER_DESCRIPTION = "databricks_10_4_med_memory_cluster"

config_service = ConfigurationService(DAG_NAME)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
dw_bucket = config_service.get_config("dw_bucket")
spectrum_iam_role = config_service.get_config("spectrum_iam_role")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")

dw_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/{DAG_NAME}/"
pipeline_config = config_service.get_config("pipeline") or {}

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
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
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


def build_tasks_dependency(create_cluster_task, terminate_cluster_task, entities_tasks):
    dependencies_list = []
    for entity_name, entity_pipeline in pipeline_config.items():
        dependencies = entity_pipeline["dw"].get("depends_on", [])
        dependencies_list += dependencies
        entity_task = entities_tasks[entity_name]

        if not dependencies:
            create_cluster_task >> entity_task["first_task"]
        else:
            for dep_entity_name in dependencies:
                dep_task = entities_tasks[dep_entity_name]
                entity_task["first_task"].set_upstream(dep_task["last_tasks"])

    dependencies_list = list(set(dependencies_list))
    for entity_name, entity_pipeline in pipeline_config.items():
        entity_task = entities_tasks[entity_name]
        if entity_name not in dependencies_list:
            terminate_cluster_task.set_upstream(entity_task["last_tasks"])


entities_tasks = {}
for entity_name, entity_pipeline in pipeline_config.items():
    dw_workflow_config = entity_pipeline["dw"]
    try:
        table = dw_workflow_config["table"]
        runs_on = dw_workflow_config["runs_on"]
    except KeyError as ex:
        raise KeyError(
            f"m=build_table_tasks, key_not_found={ex.args[0]}, msg=Config not found. You must "
            f"provide all the required task configs in the pipeline configuration in "
            f"the YAML file."
        )

    slugged_table_name = table.replace("_", "-")
    create_table_in_datalake_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=dag,
        task_id=f"create-{slugged_table_name}-in-datalake",
        pool=f"datamarts_{runs_on}",
        json={
            "spark_python_task": {
                "python_file": f"{dw_spark_jobs_path}create_datamart_table_in_datalake.py",
                "parameters": [
                    ENV,
                    dw_bucket,
                    athena_query_results_bucket,
                    DW_SCHEMA,
                    DAG_NAME,
                    table,
                    runs_on,
                ],
            }
        },
    )

    sync_metastore_table_structure_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"sync-hive-metastore-{slugged_table_name}-table-structure",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": f"{base_spark_jobs_path}sync_metastore_tables_structure.py",
                "parameters": [
                    dw_bucket,
                    LayerEnum.DW.value,
                    DW_SCHEMA,
                    "--table-name",
                    table,
                ],
            }
        },
    )

    sync_metastore_table_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"sync-hive-metastore-{slugged_table_name}-table-partitions",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": f"{base_spark_jobs_path}sync_metastore_tables_partitions.py",
                "parameters": [
                    dw_bucket,
                    LayerEnum.DW.value,
                    DW_SCHEMA,
                    "--table-name",
                    table,
                ],
            }
        },
    )

    if DAGMetadataService.metadata_file_exists(DAG_NAME, LayerEnum.DW.value, table):
        propagate_table_metadata_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=dag,
            task_id=f"propagate-table-metadata-dw-{slugged_table_name}",
            json={
                "spark_python_task": {
                    "python_file": f"{base_spark_jobs_path}propagate_table_metadata.py",
                    "parameters": [
                        LayerEnum.DW.value,
                        MetadataTypeEnum.LINEAGE.value,
                        DW_SCHEMA,
                        table,
                    ],
                }
            },
        )

        sync_metastore_table_partitions_task.set_downstream(
            propagate_table_metadata_task
        )
        last_tasks = [propagate_table_metadata_task]
    else:
        last_tasks = [sync_metastore_table_partitions_task]

    chain(
        create_table_in_datalake_task,
        sync_metastore_table_structure_task,
        sync_metastore_table_partitions_task,
    )

    if runs_on == "athena":
        load_table_into_redshift_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=dag,
            task_id=f"load-{slugged_table_name}-into-redshift",
            json={
                "spark_python_task": {
                    "python_file": f"{dw_spark_jobs_path}load_datamart_table_into_redshift.py",
                    "parameters": [ENV, dw_bucket, spectrum_iam_role, DW_SCHEMA, table],
                }
            },
        )
        create_table_in_datalake_task.set_downstream(load_table_into_redshift_task)
        last_tasks.append(load_table_into_redshift_task)

    entities_tasks.update(
        {
            entity_name: {
                "first_task": create_table_in_datalake_task,
                "last_tasks": last_tasks,
            }
        }
    )

build_tasks_dependency(create_cluster_task, terminate_cluster_task, entities_tasks)
