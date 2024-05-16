import collections
import re
import os
import json
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG, DagBag
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import cross_downstream
from airflow.operators.python_operator import PythonOperator
from airflow.hooks.S3_hook import S3Hook
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum


# Pipeline inputs
SOURCE = "dag_inventory"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2019, 8, 21, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "10 21 * * *"
CLUSTER_DESCRIPTION = "databricks_10_4_med_io-memory_photon_cluster"
PARTITION_COLS = ["year", "month", "day"]

config_service = ConfigurationService(SOURCE)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
dw_bucket = config_service.get_config("dw_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
raw_spark_job_file = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/load_{SOURCE}_raw.py"
)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")
tables = config_service.get_config("tables_list")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
ENV = os.environ.get("ENVIRONMENT")

QUERY_PATH = DAGPackagesPathService.get_dag_path(SOURCE) + "/queries/raw/"

# Regex to identify the task that initializes the cluster
# Matches create-cluster, execute-job-cluster, create-cluster-1, execute-job-cluster-1, etc.
INIT_CLUSTER_REGEX = r"^(?:create|execute-job)-cluster(?:-\d+)?$"

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
    cluster_configuration=cluster_configuration,
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
    relative_query_path=SOURCE,
    spark_jobs_path=base_spark_jobs_path,
    athena_query_result_location=athena_query_results_bucket,
)


def get_init_cluster_task_name(dag: DAG) -> str:
    """Returns the name of the task that initializes the cluster."""
    for task in dag.task_ids:
        if re.match(INIT_CLUSTER_REGEX, task):
            return task
    return None


def find_dag_configs(dag_bag: DagBag) -> list:
    """Returns a list of dictionaries containing the DAG name, location and cluster configuration."""

    dag_configs = []
    for dag_name, dag in dag_bag.dags.items():

        init_cluster_task = get_init_cluster_task_name(dag)
        if not init_cluster_task:
            continue

        create_cluster = dag.get_task(init_cluster_task)
        dag_configs.append(
            {
                "dag": dag_name,
                "dag_location": dag.filepath,
                "cluster_configuration": create_cluster.cluster_configuration,
            }
        )
    return dag_configs


def is_sync_metadata_task(task) -> bool:
    """Returns True if the task is a sync_metadata task, False otherwise."""

    if not hasattr(task, "json"):
        return False
    if "spark_python_task" not in task.json:
        return False
    if not task.json["spark_python_task"]["python_file"].endswith(
        "sync_metadata.py"
    ) and not task.json["spark_python_task"]["python_file"].endswith(
        "sync_metastore_tables_structure.py"
    ):
        return False
    return True


def get_load_task_name_from_metadata_task(metadata_task) -> str:
    """Returns the name of the task that loads the table from the metadata task."""
    # Usually, the load task is the first upstream task of the metadata task
    previous_task = metadata_task.upstream_list[0]
    # In tables with Delta, the sync_metadata task is preceded by a register task instead of load
    if previous_task.task_id.startswith("register-"):
        previous_task = previous_task.upstream_list[0]
    return previous_task.task_id


MetadataTaskParameters = collections.namedtuple("MetadataTaskParameters", ["bucket", "layer", "database", "table_name", "is_delta"])
def extract_parameters_from_sync_metadata_task(task) -> MetadataTaskParameters:
    """Extracts the parameters from the sync_metadata task."""
    params = task.json["spark_python_task"]["parameters"]
    bucket = params[0]
    layer = params[1]
    database = params[2]
    sync_mode = params[3]
    if sync_mode == "--table-name":
        table_name = params[4]
    else:
        table_name = None
    previous_task = task.upstream_list[0]
    is_delta = previous_task.task_id.startswith("register-")
    return MetadataTaskParameters(
        bucket=bucket, layer=layer, database=database, table_name=table_name, is_delta=is_delta
    )


def find_tables_generated_by_dag(dag_bag: DagBag) -> dict:
    """
    Returns a dictionary containing the tables generated by the DAG.
    In order to do that, it finds all the sync_metadata tasks. We can extract its parameters to find the table name,
    bucket, and other parameters, since it is standardized across all DAGs.
    """
    mapping = []
    for dag_name, dag in dag_bag.dags.items():
        if not get_init_cluster_task_name(dag):
            continue
        for task in dag.tasks:
            if not is_sync_metadata_task(task):
                continue
            load_task_name = get_load_task_name_from_metadata_task(task)
            task_parameters = extract_parameters_from_sync_metadata_task(
                task
            )
            mapping.append(
                {
                    "dag": dag_name,
                    "task": load_task_name,
                    "database": task_parameters.database,
                    "table": task_parameters.table_name,
                    "layer": task_parameters.layer,
                    "bucket": task_parameters.bucket,
                    "is_delta": task_parameters.is_delta,
                }
            )
    return mapping


def extract_table_to_s3(table_name: str, **kwargs) -> None:
    """Collects data from the DagBag and extracts it to S3."""

    dag_bag = DagBag(store_serialized_dags=True, include_examples=False)
    dag_bag.collect_dags_from_db()
    extract_functions = {"dag": find_dag_configs, "table": find_tables_generated_by_dag}
    if table_name not in extract_functions:
        raise KeyError(f"{table_name} does not have an extraction function configured.")

    table_data = extract_functions.get(table_name)(dag_bag)
    hook = S3Hook(aws_conn_id="aws_default")
    execution_date = kwargs["execution_date"]
    partition_path = f"year={execution_date.year}/month={execution_date.month}/day={execution_date.day}"
    hook.load_string(
        string_data=json.dumps(table_data),
        key=f"raw/dag_inventory/dag_bag_content/{table_name}/{partition_path}/{table_name}.json",
        bucket_name=datalake_bucket,
        replace=True,
    )


def create_extraction_task(table_name: str) -> PythonOperator:
    return PythonOperator(
        dag=dag,
        task_id=f"extract-{table_name}-from-dagbag-to-s3",
        python_callable=extract_table_to_s3,
        op_kwargs={"table_name": table_name},
        provide_context=True,
    )


for table_name in tables:
    load_raw_to_s3_task = create_extraction_task(table_name=table_name)

    extra_parameters = [dw_bucket, SOURCE, table_name, "{{ ds }}"]

    raw_task_group = task_group.build_raw_task_group_for_single_table(
        source=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        extraction_spark_job_file=raw_spark_job_file,
        raw_spark_job_extra_args=extra_parameters,
    )

    clean_task_group = task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        is_incremental=True,
        partitions=PARTITION_COLS,
    )

    create_cluster_task.set_upstream(load_raw_to_s3_task)
    create_cluster_task.set_downstream(DatalakeTaskGroup.first_tasks(raw_task_group))

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))
