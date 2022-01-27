import os
from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG
from bietlejuice.jobs.composer.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

# DAG params
SCHEMA = "datamarts"
CONTEXT = "for_rent"
DAG_NAME = f"dw_{SCHEMA}_{CONTEXT}"
DAG_ID = f"bietlejuice.dw_{SCHEMA}_{CONTEXT}"
INTERMEDIATE_PATH = f'dw_{SCHEMA}/{CONTEXT}'
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(dag_name=DAG_NAME, intermediate_path=INTERMEDIATE_PATH)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
dw_bucket = config_service.get_config("dw_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
spectrum_iam_role = config_service.get_config("spectrum_iam_role")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")


local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 1, 15, 0, 0, 0, tzinfo=local_tz)

# S3 paths setup
SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{INTERMEDIATE_PATH}/"
BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"

# cluster setup
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_datamarts_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{spark_jobs_logs_path}{DAG_ID}"
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

pipeline_config = config_service.get_config('pipeline') or {}

DW_SCHEMA = f"{SCHEMA}_{CONTEXT}"

def validate_pipeline_steps(entity_name, entity_pipeline):
    if "dw" not in entity_pipeline:
        raise RuntimeError(
            f"m=validate_pipeline_steps, entity={entity_name}, msg=you must provide the dw "
            f"step configuration for this entity."
        )


def get_option(task_configs, option_key):
    """
    Extract the task configuration from YAML file and check for missing config params.
    :param task_configs: the pipeline configs from YAML
    :param option_key: The YAML property
    :return: string
    """

    option = task_configs.get(option_key, False)
    if not option:
        raise RuntimeError(
            f"m=get_option, yaml_property={option},  msg=Config not found. You must "
            f"provide all the required task configs in the pipeline configuration in "
            f"the YAML file."
        )

    return option


def build_table_tasks(entity_name, entity_pipeline):

    validate_pipeline_steps(entity_name, entity_pipeline)

    sql_file = get_option(entity_pipeline["dw"], "sql_file")
    table = get_option(entity_pipeline["dw"], "table")
    schema = get_option(
        entity_pipeline["dw"], "schema"
    )  # TODO this value is not used in the job
    runs_on = get_option(entity_pipeline["dw"], "runs_on")

    slugged_table_name = table.replace("_", "-")
    create_table_in_datalake_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=DAG,
        task_id=f"create-{slugged_table_name}-in-datalake",
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}create_datamart_table_in_datalake.py",
                "parameters": [ENV, dw_bucket, athena_query_results_bucket, DW_SCHEMA, schema, table, sql_file, runs_on],
            }
        },
    )

    load_table_into_redshift_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=DAG,
        task_id=f"load-{slugged_table_name}-into-redshift",
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}load_datamart_table_into_redshift.py",
                "parameters": [ENV, dw_bucket, spectrum_iam_role, DW_SCHEMA, table],
            }
        },
    )

    sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"sync-hive-metastore-{slugged_table_name}-table",
        dag=DAG,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables_structure.py",
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

    create_table_in_datalake_task.set_downstream(
        [sync_metastore_table_task, load_table_into_redshift_task]
    )

    return {entity_name: {"first_task": create_table_in_datalake_task, "last_tasks": [sync_metastore_table_task, load_table_into_redshift_task]}}


# DAG definition
DAG = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

# Tasks definition
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=DAG,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=DAG, task_id="terminate-cluster"
)


def build_tasks():
    entities_tasks = {}
    for entity_name, entity_pipeline in pipeline_config.items():
        entity_tasks = build_table_tasks(entity_name, entity_pipeline)
        entities_tasks.update(entity_tasks)

    return entities_tasks


def build_tasks_dependency(create_cluster_task, terminate_cluster_task, entities_tasks):
    dependencies_list = []
    for entity_name, entity_pipeline in pipeline_config.items():
        dependencies = entity_pipeline["dw"].get("depends_on", [])
        dependencies_list += dependencies
        entity_task = entities_tasks[entity_name]       #DAG.task_dict[entity_name]

        if not dependencies:
            create_cluster_task >> entity_task["first_task"]
        else:
            for dep_entity_name in dependencies:
                dep_task = entities_tasks[dep_entity_name] #DAG.task_dict[dep_entity_name]
                entity_task["first_task"].set_upstream(dep_task["last_tasks"])

    dependencies_list = list(set(dependencies_list))
    for entity_name, entity_pipeline in pipeline_config.items():
        entity_task = entities_tasks[entity_name]  #DAG.task_dict[entity_name]
        if entity_name not in dependencies_list:
            terminate_cluster_task.set_upstream(entity_task["last_tasks"])


if pipeline_config and pipeline_config.items():
    entities_tasks = build_tasks()
    build_tasks_dependency(create_cluster_task, terminate_cluster_task, entities_tasks)
else:
    create_cluster_task >> terminate_cluster_task
