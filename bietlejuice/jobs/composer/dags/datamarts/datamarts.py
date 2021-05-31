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
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
from bietlejuice.jobs.composer.services import FileService

# DAG params
DAG_NAME = "datamarts"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 1, 15, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 9 * * *"

# S3 paths setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{DAG_NAME}/"
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_NAME
)

# cluster setup
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_datamarts_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

config_file_path = os.path.join(
    os.path.dirname(os.path.realpath(__file__)), f"{DAG_NAME}.yml"
)
pipeline_config = FileService.get_dict_from_yaml_file(config_file_path).get(
    "pipeline", {}
)

DW_BUCKET = Variable.get("dw_bucket")
DW_SCHEMA = "datamarts"


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


def build_entity_subdag(subdag_name, entity_name, entity_pipeline):
    entity_subdag = BaseSubDAG(
        sub_dag_name=subdag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    validate_pipeline_steps(entity_name, entity_pipeline)

    sql_file = get_option(entity_pipeline["dw"], "sql_file")
    table = get_option(entity_pipeline["dw"], "table")
    schema = get_option(
        entity_pipeline["dw"], "schema"
    )  # TODO this value is not used in the job

    slugged_table_name = table.replace("_", "-")
    create_table_in_datalake_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=entity_subdag,
        task_id=f"create-{slugged_table_name}-in-datalake",
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}create_datamart_table_in_datalake.py",
                "parameters": [ENV, DW_BUCKET, DW_SCHEMA, schema, table, sql_file],
            }
        },
    )

    load_table_into_redshift_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=entity_subdag,
        task_id=f"load-{slugged_table_name}-into-redshift",
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}load_datamart_table_into_redshift.py",
                "parameters": [ENV, DW_BUCKET, SPECTRUM_IAM_ROLE, DW_SCHEMA, table],
            }
        },
    )

    sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"sync-hive-metastore-{slugged_table_name}-table",
        dag=entity_subdag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables.py",
                "parameters": [
                    DW_BUCKET,
                    LayerEnum.DW.value,
                    DW_SCHEMA,
                    "--table-name",
                    table,
                ],
            }
        },
    )

    validate_sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=entity_subdag,
        task_id=f"validate-sync-hive-metastore-{slugged_table_name}-table",
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH
                + "validate_sync_metastore_tables.py",
                "parameters": [LayerEnum.DW.value, DW_SCHEMA, "--table-name", table],
            }
        },
    )

    create_table_in_datalake_task >> sync_metastore_table_task >> validate_sync_metastore_table_task
    create_table_in_datalake_task >> load_table_into_redshift_task

    return entity_subdag


# DAG definition
DAG = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
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
    for entity_name, entity_pipeline in pipeline_config.items():
        BaseSubDAG.get_sub_dag_operator(
            dag=DAG,
            sub_dag_name=entity_name,
            sub_dag_func=build_entity_subdag,
            entity_name=entity_name,
            entity_pipeline=entity_pipeline,
        )


def build_tasks_dependency(create_cluster_task, terminate_cluster_task):
    dependencies_list = []
    for entity_name, entity_pipeline in pipeline_config.items():
        dependencies = entity_pipeline["dw"].get("depends_on", [])
        dependencies_list += dependencies
        entity_task = DAG.task_dict[entity_name]

        if not dependencies:
            create_cluster_task >> entity_task
        else:
            for dep_entity_name in dependencies:
                dep_task = DAG.task_dict[dep_entity_name]
                entity_task.set_upstream(dep_task)

    dependencies_list = list(set(dependencies_list))
    for entity_name, entity_pipeline in pipeline_config.items():
        entity_task = DAG.task_dict[entity_name]
        if entity_name not in dependencies_list:
            entity_task >> terminate_cluster_task


if pipeline_config and pipeline_config.items():
    build_tasks()
    build_tasks_dependency(create_cluster_task, terminate_cluster_task)
else:
    create_cluster_task >> terminate_cluster_task
