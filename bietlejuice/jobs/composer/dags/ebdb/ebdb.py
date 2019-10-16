from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG

# DAG params
DAG_ID = "ebdb"
FULL_DAG_ID = "bietlejuice.{}".format(DAG_ID)
ENV = Variable.get("environment")
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 22 * * *"

# Job params
SOURCE = "ebdb"
DW_SCHEMA = "public_spark"

# s3 path setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = S3_PREFIX + "/spark_jobs/{}/".format(DAG_ID)
LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

# cluster params
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
CLUSTER_DESCRIPTION["num_workers"] = 6

# cluster libraries
DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {"jar": "s3://5a-artifacts/mysql-connector-java/mysql-connector-java-5.1.47.jar"}
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES


# methods to create tasks and subdags
def create_clean_table_in_datalake_task(local_dag, table_name, source, env, dag_name):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-clean-{}-in-datalake".format(table_name.replace("_", "-")),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_clean_table_in_datalake.py",
                "parameters": [table_name, source, env, dag_name],
            }
        },
    )


def create_dw_table_in_datalake_task(local_dag, table_name, schema, env, dag_name):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-dw-{}-{}-in-datalake".format(
            schema, table_name.replace("_", "-")
        ),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_dw_table_in_datalake.py",
                "parameters": [table_name, schema, env, dag_name],
            }
        },
    )


def load_dw_table_into_redshift_task(local_dag, table_name, schema, env):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="load-dw-{}-{}-in-datalake".format(
            schema, table_name.replace("_", "-")
        ),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "load_dw_table_into_redshift.py",
                "parameters": [table_name, schema, env],
            }
        },
    )


def create_all_external_tables_task(local_dag, env, datalake_layer, source):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-all-{}-{}-external-tables".format(source, datalake_layer),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_external_tables.py",
                "parameters": [env, datalake_layer, source, "--all"],
            }
        },
    )


def create_external_tables_task(local_dag, env, datalake_layer, source, tables):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-{}-external-tables".format(datalake_layer),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_external_tables.py",
                "parameters": [env, datalake_layer, source, "--tables"] + tables,
            }
        },
    )


def create_clean_and_dim_tables_sub_dag(
    sub_dag_name, source, clean_table, dw_schema, dim_table
):
    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=FULL_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()
    clean_table_task = create_clean_table_in_datalake_task(
        local_dag, clean_table, source, ENV, DAG_ID
    )
    dim_table_task = create_dw_table_in_datalake_task(
        local_dag, dim_table, dw_schema, ENV, DAG_ID
    )
    load_dim_table_task = load_dw_table_into_redshift_task(
        local_dag, dim_table, dw_schema, ENV
    )
    create_clean_external_tables_task = create_external_tables_task(
        local_dag, ENV, "clean", source, [clean_table]
    )
    clean_table_task >> dim_table_task >> load_dim_table_task
    clean_table_task >> create_clean_external_tables_task

    return local_dag


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
    max_active_runs=1,
    catchup=False,
)

# tasks and subdags definitions
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

ebdb_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="ebdb-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "load_ebdb_into_datalake.py",
            "parameters": [ENV],
        }
    },
)

create_raw_external_tables_task = create_all_external_tables_task(
    dag, ENV, "raw", "ebdb"
)

condo_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="condo",
    sub_dag_func=create_clean_and_dim_tables_sub_dag,
    source=SOURCE,
    clean_table="condo",
    dw_schema=DW_SCHEMA,
    dim_table="dim_condo",
)

region_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="region",
    sub_dag_func=create_clean_and_dim_tables_sub_dag,
    source=SOURCE,
    clean_table="region",
    dw_schema=DW_SCHEMA,
    dim_table="dim_region",
)

visit_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="visit",
    sub_dag_func=create_clean_and_dim_tables_sub_dag,
    source=SOURCE,
    clean_table="visit",
    dw_schema=DW_SCHEMA,
    dim_table="dim_visit",
)

contract_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="contract",
    sub_dag_func=create_clean_and_dim_tables_sub_dag,
    source=SOURCE,
    clean_table="contract",
    dw_schema=DW_SCHEMA,
    dim_table="dim_contract",
)

inspection_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="inspection",
    sub_dag_func=create_clean_and_dim_tables_sub_dag,
    source=SOURCE,
    clean_table="inspection",
    dw_schema=DW_SCHEMA,
    dim_table="dim_inspection",
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

# tasks dependencies
create_cluster_task >> ebdb_to_datalake_raw_task
ebdb_to_datalake_raw_task >> [
    create_raw_external_tables_task,
    condo_sub_dag_task,
    region_sub_dag_task,
    visit_sub_dag_task,
    contract_sub_dag_task,
    inspection_sub_dag_task,
] >> terminate_cluster_task
