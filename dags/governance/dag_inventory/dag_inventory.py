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
INIT_CLUSTER_TASKS = ["create-cluster", "execute-job-cluster"]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DEFAULT_OWNER,
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


def get_init_cluster_task(dag: DAG):
    for task in INIT_CLUSTER_TASKS:
        if task in dag.task_ids:
            return task

    return None


def find_dag_configs(dag_bag: DagBag) -> dict:
    dag_configs = []
    for dag_name, dag in dag_bag.dags.items():

        init_cluster_task = get_init_cluster_task(dag)
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


def find_tables_generated_by_dag(dag_bag: DagBag) -> dict:
    mapping = []
    for dag_name, dag in dag_bag.dags.items():
        if not any(task in dag.task_ids for task in INIT_CLUSTER_TASKS):
            continue
        for task in dag.tasks:
            if not hasattr(task, "json"):
                continue
            if "spark_python_task" not in task.json:
                continue
            if not task.json["spark_python_task"]["python_file"].endswith(
                "sync_metadata.py"
            ) and not task.json["spark_python_task"]["python_file"].endswith(
                "sync_metastore_tables_structure.py"
            ):
                continue
            upstream = task.upstream_list[0].task_id
            params = task.json["spark_python_task"]["parameters"]
            bucket = params[0]
            layer = params[1]
            database = params[2]
            sync_mode = params[3]
            if sync_mode == "--table-name":
                table_name = params[4]
            else:
                table_name = None
            mapping.append(
                {
                    "dag": dag_name,
                    "task": upstream,
                    "database": database,
                    "table": table_name,
                    "layer": layer,
                    "bucket": bucket,
                }
            )
    return mapping


def extract_table_to_s3(table_name: str, **kwargs) -> None:
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
