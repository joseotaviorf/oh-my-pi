from datetime import datetime, timedelta

import pendulum
import os
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import cross_downstream, chain

from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.jobs.composer.services.file_service import FileService

# DAG params
DAG_ID = "ebdb"
FULL_DAG_ID = "bietlejuice.{}".format(DAG_ID)
ENV = os.environ.get("ENVIRONMENT")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "10 21 * * *"
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

# Job params
SOURCE = "ebdb"
DW_SCHEMA = "quintoandar"
DW_BUCKET = Variable.get("dw_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")

# s3 path setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
EBDB_SPARK_JOBS_PATH = S3_PREFIX + "/spark_jobs/{}/".format(DAG_ID)
LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
CREATE_CLEAN_TABLE_IN_DATA_LAKE_PATH = (
    EBDB_SPARK_JOBS_PATH + "create_clean_table_in_datalake.py"
)
CREATE_EXTERNAL_TABLES_FILE_PATH = EBDB_SPARK_JOBS_PATH + "create_external_tables.py"
LOAD_DB_SCHEMA_INTO_DATALAKE_RAW_FILE_PATH = (
    EBDB_SPARK_JOBS_PATH + "load_ebdb_into_datalake.py"
)

# cluster params
CLUSTER_DESCRIPTION = Variable.get("databricks_ebdb_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# cluster libraries
DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {
        "jar": f"{ARTIFACTS_S3_BUCKET}/mysql-connector-java/mysql-connector-java-5.1"
        f".47.jar"
    }
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

RAW_EXECUTION_TIMEOUT_HOURS = 3.5

# dag definition
dag = DAG(
    dag_id=FULL_DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    catchup=False,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=DOC_MD_BASE_URL, dag_id=FULL_DAG_ID
    ),
)


def dw_tasks(table_name):
    """
    Mounts the DW workflow for each table.

    :return: the first and last tasks from the clean workflow slice.
    :rtype: List[str, List[str]]
    """
    slugged_table_name = table_name.replace("_", "-")
    dim_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"create-dw-{DW_SCHEMA}-{slugged_table_name}-in-datalake",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": EBDB_SPARK_JOBS_PATH + "create_dw_table_in_datalake.py",
                "parameters": [table_name, DW_BUCKET, DW_SCHEMA, ENV, DAG_ID],
            }
        },
    )

    load_dim_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-dw-{DW_SCHEMA}-{slugged_table_name}-in-datalake",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": EBDB_SPARK_JOBS_PATH + "load_dw_table_into_redshift.py",
                "parameters": [
                    SPECTRUM_IAM_ROLE,
                    table_name,
                    DW_BUCKET,
                    DW_SCHEMA,
                    ENV,
                ],
            }
        },
    )

    sync_metastore_dw_table_structure_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=dag,
        task_id=f"sync-hive-metastore-dw-{slugged_table_name}-structure",
        json={
            "spark_python_task": {
                "python_file": f"{BASE_SPARK_JOBS_PATH}/sync_metastore_tables_structure.py",
                "parameters": [
                    DW_BUCKET,
                    LayerEnum.DW.value,
                    DW_SCHEMA,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    chain(dim_table_task, [sync_metastore_dw_table_structure_task, load_dim_table_task])

    return [
        dim_table_task,
        [load_dim_table_task, sync_metastore_dw_table_structure_task],
    ]


def clean_tasks(table_name):
    """
    Mounts the clean workflow for each table.

    :return: the first and last tasks from the clean workflow slice.
    :rtype: List[str, List[str]]
    """
    slugged_table_name = table_name.replace("_", "-")
    clean_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=dag,
        task_id=f"create-clean-{slugged_table_name}-in-data-lake",
        json={
            "spark_python_task": {
                "python_file": CREATE_CLEAN_TABLE_IN_DATA_LAKE_PATH,
                "parameters": [
                    table_name,
                    SOURCE,
                    ENV,
                    DATALAKE_BUCKET,
                    DAG_ID,
                    "clean",
                ],
            }
        },
    )

    create_clean_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=dag,
        task_id=f"create-{slugged_table_name}-clean-external-table",
        pool="athena",
        json={
            "spark_python_task": {
                "python_file": CREATE_EXTERNAL_TABLES_FILE_PATH,
                "parameters": [
                    ENV,
                    ATHENA_QUERY_RESULT_LOCATION,
                    "clean",
                    DATALAKE_BUCKET,
                    SOURCE,
                    "--tables",
                ]
                + [table_name],
            }
        },
    )

    sync_metastore_clean_table_structure_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=dag,
        task_id=f"sync-hive-metastore-clean-{slugged_table_name}-structure",
        json={
            "spark_python_task": {
                "python_file": f"{BASE_SPARK_JOBS_PATH}/sync_metastore_tables_structure.py",
                "parameters": [
                    DATALAKE_BUCKET,
                    LayerEnum.CLEAN.value,
                    SOURCE,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    final_task = sync_metastore_clean_table_structure_task
    if FileService.metadata_file_exists(SOURCE, LayerEnum.CLEAN.value, table_name):
        propagate_table_metadata_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=dag,
            task_id=f"propagate-table-metadata-clean-{slugged_table_name}",
            json={
                "spark_python_task": {
                    "python_file": f"{BASE_SPARK_JOBS_PATH}/propagate_table_metadata.py",
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
    clean_table_task >> create_clean_external_tables_task

    return [clean_table_task, [create_clean_external_tables_task, final_task]]


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
                "python_file": LOAD_DB_SCHEMA_INTO_DATALAKE_RAW_FILE_PATH,
                "parameters": [ENV, DATALAKE_BUCKET],
            }
        },
        execution_timeout=timedelta(hours=RAW_EXECUTION_TIMEOUT_HOURS),
    )

    create_raw_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-all-raw-external-tables",
        dag=dag,
        pool="athena",
        json={
            "spark_python_task": {
                "python_file": CREATE_EXTERNAL_TABLES_FILE_PATH,
                "parameters": [
                    ENV,
                    ATHENA_QUERY_RESULT_LOCATION,
                    "raw",
                    DATALAKE_BUCKET,
                    SOURCE,
                    "--all",
                ],
            }
        },
    )

    load_tables_into_datalake_task >> create_raw_external_tables_task

    return [load_tables_into_datalake_task, create_raw_external_tables_task]


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
    file_list = FileService.list_layer_sql_files(SOURCE, layer)
    task_list = {}

    for file_name in file_list:
        table_name = FileService.remove_file_extension(file_name)
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


# Tasks definitions
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

polygon_region_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id="polygon_region_to_datalake_raw",
    json={
        "spark_python_task": {
            "python_file": EBDB_SPARK_JOBS_PATH + "load_query_table_in_datalake.py",
            "parameters": [ENV, DATALAKE_BUCKET, "poligonoregiao", SOURCE],
        }
    },
)

sync_metastore_table_structure_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"sync-hive-metastore-raw-structure",
    json={
        "spark_python_task": {
            "python_file": f"{BASE_SPARK_JOBS_PATH}/sync_metastore_tables_structure.py",
            "parameters": [
                DATALAKE_BUCKET,
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
            "python_file": f"{BASE_SPARK_JOBS_PATH}/propagate_raw_tables_metadata.py",
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
clean_task_list = build_layer_task_list("clean")
dw_sub_dags = build_layer_task_list("dw")

# create-cluster >> downstream
create_cluster_task >> [
    task_list_first_task(raw_task_list),
    polygon_region_to_datalake_raw_task,
]

# raw >> hive sync
chain(task_list_first_task(raw_task_list), sync_metastore_table_structure_task)

# hive sync raw >> propagate metadata for raw
chain(sync_metastore_table_structure_task, propagate_table_lineage_task)

# raw >> clean
chain(
    task_list_first_task(raw_task_list),
    [task_list_first_task(c) for c in clean_task_list.values()],
)

polygon_region_to_datalake_raw_task >> task_list_first_task(
    clean_task_list["polygon_region"]
)

# clean >> dw
cross_downstream(
    task_list_last_tasks(clean_task_list.pop("proponent_proposal")),
    [
        task_list_first_task(dw_sub_dags["dim_proposal_person"]),
        task_list_first_task(dw_sub_dags["fact_proposal_people"]),
    ],
)

cross_downstream(
    task_list_last_tasks(clean_task_list.pop("proposal")),
    task_list_first_task(dw_sub_dags["fact_proposal_people"]),
)

cross_downstream(
    task_list_last_tasks(clean_task_list.pop("user")),
    [
        task_list_first_task(dw_sub_dags["fact_contract_people"]),
        task_list_first_task(dw_sub_dags["fact_proposal_people"]),
    ],
)

contract_model_dependencies = []
contract_model_dependencies.extend(
    task_list_last_tasks(clean_task_list.pop("contract"))
)
contract_model_dependencies.extend(
    task_list_last_tasks(clean_task_list.pop("contract_person"))
)
contract_model_dependencies.extend(
    task_list_last_tasks(clean_task_list.pop("rent_flow"))
)
contract_model_dependencies.extend(task_list_last_tasks(clean_task_list.pop("house")))
contract_model_dependencies.extend(
    task_list_last_tasks(clean_task_list.pop("partner_agent"))
)
contract_model_dependencies.extend(
    task_list_last_tasks(clean_task_list.pop("conversion_lead"))
)
contract_model_dependencies.extend(task_list_last_tasks(clean_task_list.pop("lead")))

cross_downstream(
    contract_model_dependencies,
    [
        task_list_first_task(dw_sub_dags["dim_contract_person"]),
        task_list_first_task(dw_sub_dags["fact_contract_people"]),
    ],
)

# upstream >> terminate-cluster
cross_downstream(
    [propagate_table_lineage_task] + task_list_last_tasks(raw_task_list),
    terminate_cluster_task,
)

for task_list in clean_task_list.values():
    cross_downstream(task_list_last_tasks(task_list), terminate_cluster_task)

for task_list in dw_sub_dags.values():
    cross_downstream(task_list_last_tasks(task_list), terminate_cluster_task)
