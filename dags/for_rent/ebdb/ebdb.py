import os
from datetime import datetime, timedelta
from pendulum import timezone

from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import cross_downstream, chain

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.formatters import StringFormatter
from bietlejuice.services import ConfigurationService
from bietlejuice.services.dag_metadata_service import DAGMetadataService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

# Pipeline inputs
SOURCE = "ebdb"
DAG_ID = "bietlejuice.{}".format(SOURCE)
MAIN_START_DATE = datetime(2019, 5, 31, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "10 21 * * *"

config_service = ConfigurationService(SOURCE)
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
default_libraries = config_service.get_config("default_libraries")
cluster_configuration = config_service.get_config("custom_cluster")

EBDB_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/"
RAW_SPARK_JOB_FILE = EBDB_SPARK_JOBS_PATH + "load_ebdb_raw.py"
CLEAN_SPARK_JOB_PATH = EBDB_SPARK_JOBS_PATH + "load_ebdb_clean.py"

CUSTOM_LIBRARIES = [{"maven": {"coordinates": "mysql:mysql-connector-java:8.0.30"}}]

RAW_EXECUTION_TIMEOUT_HOURS = 3.5

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
    catchup=False,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)


def clean_tasks(table_name):
    """
    Mounts the clean workflow for each table.

    :return: the first and last tasks from the clean workflow slice.
    :rtype: List[str, List[str]]
    """
    slugged_table_name = table_name.replace("_", "-")
    clean_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=dag,
        task_id=DatalakeTaskGroup.generate_default_task_id(
            task_prefix=DatalakeTaskGroup.LOAD_TASK_PREFIX,
            layer=LayerEnum.CLEAN,
            schema=SOURCE,
            table_name=table_name,
        ),
        json={
            "spark_python_task": {
                "python_file": CLEAN_SPARK_JOB_PATH,
                "parameters": [ENV, datalake_bucket, table_name, SOURCE],
            }
        },
    )

    sync_metastore_clean_table_structure_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=dag,
        task_id=f"sync-hive-metastore-clean-{slugged_table_name}-structure",
        json={
            "spark_python_task": {
                "python_file": f"{EBDB_SPARK_JOBS_PATH}/sync_metastore_tables_structure.py",
                "parameters": [
                    datalake_bucket,
                    LayerEnum.CLEAN.value,
                    SOURCE,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    final_task = sync_metastore_clean_table_structure_task
    if DAGMetadataService.metadata_file_exists(
        SOURCE, LayerEnum.CLEAN.value, table_name
    ):
        propagate_table_metadata_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=dag,
            task_id=f"propagate-table-metadata-clean-{slugged_table_name}",
            json={
                "spark_python_task": {
                    "python_file": f"{EBDB_SPARK_JOBS_PATH}/propagate_table_metadata.py",
                    "parameters": [
                        LayerEnum.CLEAN.value,
                        MetadataTypeEnum.LINEAGE.value,
                        SOURCE,
                        table_name,
                    ],
                }
            },
        )

        sync_metastore_clean_table_structure_task >> propagate_table_metadata_task
        final_task = propagate_table_metadata_task

    chain(clean_table_task, sync_metastore_clean_table_structure_task)

    return [clean_table_task, final_task]


def build_raw_task_list():
    """
    Since we're creating a bunch of tasks now instead of using subdags, we need to make sure the same behavior occurs in
     relationships.
    Hence, zero indexing represents the first task (load-to-raw/load-to-clean/etc), which must be the single first
     relationship with upstream tasks.
    Moreover, the -1 indexing represents the last task (or tasks) from the task group, which will continue being the last
     task(s) for the initial of a downstream flow.

    :rtype: List[str]
    """
    load_tables_into_datalake_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="load-tables-to-datalake-raw",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": RAW_SPARK_JOB_FILE,
                "parameters": [ENV, datalake_bucket],
            }
        },
        execution_timeout=timedelta(hours=RAW_EXECUTION_TIMEOUT_HOURS),
    )

    return [load_tables_into_datalake_task]


def build_layer_task_list(layer):
    """
    Creates a task group for each table, according to given layer.

    Since we're creating a bunch of tasks now instead of using subdags, we need to make sure the same behavior occurs in
     relationships.
    Hence, zero indexing represents the first task (load-to-raw/load-to-clean/etc), which must be the single first
     relationship with upstream tasks.
    Moreover, the -1 indexing represents the last task (or tasks) from the task group, which will continue being the last
     task(s) for the initial of a downstream flow.

    :return: A dictionary where the key is the table name and the value is the
     task group's last and first tasks.
    """
    file_list = DAGPackagesPathService.list_queries_files_in_composer(
        dag_name=SOURCE, layer=layer
    )
    task_list = {}
    for table_name in file_list:
        task_list[table_name] = eval(f"{layer}_tasks('{table_name}')")

    return task_list


def task_list_first_task(task_list_tasks):
    """
    Gets the first task of the tasks list.

    :rtype: airflow.models.BaseOperator
    """
    return task_list_tasks[0]


def task_list_last_tasks(task_list_tasks):
    """
    Gets the last tasks list of the tasks list.
    If it is a single task, then encapsulates into a list.

    :rtype: List[airflow.models.BaseOperator]
    """
    last_tasks = task_list_tasks[-1]
    if not isinstance(last_tasks, list):
        last_tasks = [last_tasks]

    return last_tasks


create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries + CUSTOM_LIBRARIES,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

polygon_region_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id="load-polygon-region-raw",
    json={
        "spark_python_task": {
            "python_file": EBDB_SPARK_JOBS_PATH + "load_polygon_region_raw.py",
            "parameters": [ENV, datalake_bucket, "poligonoregiao", SOURCE],
        }
    },
)

sync_metastore_table_structure_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"sync-hive-metastore-raw-structure",
    json={
        "spark_python_task": {
            "python_file": f"{EBDB_SPARK_JOBS_PATH}/sync_metastore_tables_structure.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.RAW.value,
                SOURCE,
                "--all-tables",
            ],
        }
    },
)

propagate_table_lineage_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"propagate-table-metadata-raw",
    json={
        "spark_python_task": {
            "python_file": f"{EBDB_SPARK_JOBS_PATH}/propagate_raw_tables_metadata.py",
            "parameters": [
                LayerEnum.RAW.value,
                MetadataTypeEnum.FULL_CONTENT_LINEAGE.value,
                SOURCE,
                SOURCE,
                "--product-database-name",
                "ebdb",
                "--all-tables",
            ],
        }
    },
)

raw_task_list = build_raw_task_list()
clean_task_list = build_layer_task_list(LayerEnum.CLEAN.value)

# create-cluster >> downstream
create_cluster_task >> [task_list_first_task(raw_task_list), polygon_region_raw_task]

# raw >> hive sync
chain(task_list_first_task(raw_task_list), sync_metastore_table_structure_task)

# hive sync raw >> propagate metadata for raw
chain(sync_metastore_table_structure_task, propagate_table_lineage_task)

# raw >> clean
chain(
    task_list_first_task(raw_task_list),
    [task_list_first_task(c) for c in clean_task_list.values()],
)

polygon_region_raw_task >> task_list_first_task(clean_task_list["polygon_region"])

# Data Quality tests for raw
tb_names = DAGPackagesPathService.list_data_quality_tests_files_in_composer(
    dag_name=SOURCE, layer=LayerEnum.RAW.value
)

for tb_name in tb_names:
    inmetro_bucket = config_service.get_config("inmetro_bucket")
    table_name_suffix = StringFormatter.slugify(f"-{tb_name}")
    intermediate_path = ""

    data_quality_tests_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=dag,
        task_id=f"data-quality-tests-raw-{SOURCE}{table_name_suffix}",
        json={
            "spark_python_task": {
                "python_file": f"{base_spark_jobs_path}/data_quality_tests.py",
                "parameters": [
                    ENV,
                    "{{ ds }}",
                    inmetro_bucket,
                    LayerEnum.RAW.value,
                    SOURCE,
                    tb_name,
                    intermediate_path,
                ],
            }
        },
    )

    chain(
        task_list_first_task(raw_task_list),
        data_quality_tests_task,
        terminate_cluster_task,
    )

# upstream >> terminate-cluster
cross_downstream(
    [propagate_table_lineage_task] + task_list_last_tasks(raw_task_list),
    terminate_cluster_task,
)

for task_list in clean_task_list.values():
    cross_downstream(task_list_last_tasks(task_list), terminate_cluster_task)
