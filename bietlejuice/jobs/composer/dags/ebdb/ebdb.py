from datetime import datetime, timedelta

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.services.file_service import FileService

# DAG params
DAG_ID = "ebdb"
FULL_DAG_ID = "bietlejuice.{}".format(DAG_ID)
ENV = Variable.get("environment")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 22 * * *"
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

# Job params
SOURCE = "ebdb"
DW_SCHEMA = "quintoandar"
DW_BUCKET = Variable.get("dw_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")

# s3 path setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = S3_PREFIX + "/spark_jobs/{}/".format(DAG_ID)
LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
CREATE_CLEAN_TABLE_IN_DATA_LAKE_PATH = (
    SPARK_JOBS_PATH + "create_clean_table_in_datalake.py"
)
CREATE_EXTERNAL_TABLES_FILE_PATH = SPARK_JOBS_PATH + "create_external_tables.py"
LOAD_DB_SCHEMA_INTO_DATALAKE_RAW_FILE_PATH = (
    SPARK_JOBS_PATH + "load_ebdb_into_datalake.py"
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
        "owner": BaseDAG.DEFAULT_OWNER,
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


# methods to create tasks and subdags
def create_clean_table_in_datalake_task(local_dag, table_name, source, env, dag_name):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-clean-{}-in-datalake".format(table_name.replace("_", "-")),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_clean_table_in_datalake.py",
                "parameters": [table_name, source, env, DATALAKE_BUCKET, dag_name],
            }
        },
    )


def create_dw_table_in_datalake_task(table_name, schema, env, dag_name):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-dw-{}-{}-in-datalake".format(
            schema, table_name.replace("_", "-")
        ),
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_dw_table_in_datalake.py",
                "parameters": [table_name, DW_BUCKET, schema, env, dag_name],
            }
        },
    )


def load_dw_table_into_redshift_task(table_name, schema, env):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="load-dw-{}-{}-in-datalake".format(
            schema, table_name.replace("_", "-")
        ),
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "load_dw_table_into_redshift.py",
                "parameters": [SPECTRUM_IAM_ROLE, table_name, DW_BUCKET, schema, env],
            }
        },
    )


def create_external_tables_task(env, datalake_layer, source, tables):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-{}-external-tables".format(datalake_layer),
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_external_tables.py",
                "parameters": [
                    env,
                    ATHENA_QUERY_RESULT_LOCATION,
                    datalake_layer,
                    DATALAKE_BUCKET,
                    source,
                    "--tables",
                ]
                + tables,
            }
        },
    )


def dw_tasks(table_name):
    dim_table_task = create_dw_table_in_datalake_task(
        table_name, DW_SCHEMA, ENV, DAG_ID
    )
    load_dim_table_task = load_dw_table_into_redshift_task(table_name, DW_SCHEMA, ENV)

    dim_table_task >> load_dim_table_task

    return [dim_table_task, load_dim_table_task]


def clean_tasks(table_name):
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
    clean_table_task >> create_clean_external_tables_task
    return [clean_table_task, create_clean_external_tables_task]


def create_raw_tables_sub_dag_tasks(source):

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

    create_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
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
                    source,
                    "--all",
                ],
            }
        },
    )

    load_tables_into_datalake_task >> create_external_tables_task

    return [load_tables_into_datalake_task, create_external_tables_task]


def build_subdags(stage):
    # create subdag for each table
    file_list = FileService.list_layer_sql_files(SOURCE, stage)
    subdags = {}

    for file_name in file_list:
        file_name = FileService.remove_file_extension(file_name)

        subdags[file_name] = eval(f"{stage}_tasks('{file_name}')")

    # subdags is a dict where the keys are table or file names
    # and the values are corresponding subdag objects
    return subdags


# tasks and subdags definitions
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

polygon_region_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id="polygon_region_to_datalake_raw",
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "load_query_table_in_datalake.py",
            "parameters": [ENV, DATALAKE_BUCKET, "poligonoregiao", SOURCE],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

load_raw_sub_dag = create_raw_tables_sub_dag_tasks(source=SOURCE)


def cross_downstream(from_tasks, to_tasks):
    for task in from_tasks:
        task.set_downstream(to_tasks)


def subdag_first_task(subdag_task):
    return subdag_task[0]


def subdag_last_task(subdag_task):
    return subdag_task[-1]


clean_sub_dags = build_subdags("clean")
dw_sub_dags = build_subdags("dw")

# Note 1: since we're creating task lists now, we need to make sure the same behavior occurs in relationships
# hence, zero indexing represents the first task (load-to-raw/load-to-clean/etc), which must be the single first
# relationship with upstream tasks
# moreover, the -1 indexing represents the last task (create-external-table), which will continue being the last
# task for the initial of a downstream flow.

# Note 2: the task lists created here were done by such as to maintain an approximate structure for SubDags representation
# and also to make sure Airflow 2.0's TaskGroup can reuse it with little change.

create_cluster_task >> [
    subdag_first_task(load_raw_sub_dag),
    polygon_region_to_datalake_raw_task,
]
subdag_last_task(load_raw_sub_dag) >> [
    subdag_first_task(c) for c in clean_sub_dags.values()
]

polygon_region_to_datalake_raw_task >> subdag_first_task(
    clean_sub_dags["polygon_region"]
)
subdag_last_task(clean_sub_dags.pop("proponent_proposal")) >> [
    subdag_first_task(dw_sub_dags["dim_proposal_person"]),
    subdag_first_task(dw_sub_dags["fact_proposal_people"]),
]

subdag_last_task(clean_sub_dags.pop("proposal")) >> subdag_first_task(
    dw_sub_dags["fact_proposal_people"]
)

subdag_last_task(clean_sub_dags.pop("user")) >> [
    subdag_first_task(dw_sub_dags["fact_contract_people"]),
    subdag_first_task(dw_sub_dags["fact_proposal_people"]),
]

cross_downstream(
    [
        subdag_last_task(clean_sub_dags.pop("contract")),
        subdag_last_task(clean_sub_dags.pop("contract_person")),
        subdag_last_task(clean_sub_dags.pop("rent_flow")),
        subdag_last_task(clean_sub_dags.pop("house")),
        subdag_last_task(clean_sub_dags.pop("partner_agent")),
        subdag_last_task(clean_sub_dags.pop("conversion_lead")),
        subdag_last_task(clean_sub_dags.pop("lead")),
    ],
    [
        subdag_first_task(dw_sub_dags["dim_contract_person"]),
        subdag_first_task(dw_sub_dags["fact_contract_people"]),
    ],
)

[subdag_last_task(c) for c in clean_sub_dags.values()] >> terminate_cluster_task
[subdag_last_task(d) for d in dw_sub_dags.values()] >> terminate_cluster_task
