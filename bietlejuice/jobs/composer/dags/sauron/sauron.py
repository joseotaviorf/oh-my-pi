from datetime import datetime, timedelta

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG
from bietlejuice.jobs.composer.services.file_service import FileService

DAG_ID = "sauron"
FULL_DAG_ID = f"bietlejuice.{DAG_ID}"

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 10, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "30 1 * * *"

ENV = Variable.get("environment")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
SOURCE = "sauron"
schema = "public"

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

LOAD_SAURON_INTO_DATALAKE_RAW_FILE_PATH = (
    S3_PREFIX + "/spark_jobs/{}/load_sauron_into_datalake.py".format(DAG_ID)
)
CREATE_CLEAN_TABLES_IN_DATALAKE_FILE_PATH = (
    S3_PREFIX + "/spark_jobs/{}/create_clean_table_in_datalake.py".format(DAG_ID)
)
CREATE_EXTERNAL_TABLES_FILE_PATH = (
    S3_PREFIX + "/spark_jobs/{}/create_external_tables.py".format(DAG_ID)
)

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_sauron", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)


dag = DAG(
    dag_id=FULL_DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
)


def build_table_sub_dag(
    sub_dag_name,
    env,
    source,
    schema,
    table_name,
    main_dag_id,
    main_schedule_interval,
    main_start_date,
):
    table_sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=main_dag_id,
        schedule_interval=main_schedule_interval,
        start_date=main_start_date,
    )._build_local_dag()
    slugged_table_name = table_name.replace("_", "-")

    clean_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=table_sub_dag,
        task_id=f"create-clean-{slugged_table_name}-in-data-lake",
        json={
            "spark_python_task": {
                "python_file": CREATE_CLEAN_TABLES_IN_DATALAKE_FILE_PATH,
                "parameters": [table_name, DAG_ID, env, DATALAKE_BUCKET, DAG_ID],
            }
        },
    )

    create_clean_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=table_sub_dag,
        task_id=f"create-{slugged_table_name}-clean-external-table",
        json={
            "spark_python_task": {
                "python_file": CREATE_EXTERNAL_TABLES_FILE_PATH,
                "parameters": [
                    env,
                    DATALAKE_BUCKET,
                    ATHENA_QUERY_RESULT_LOCATION,
                    "clean",
                    source,
                    schema,
                    "--tables",
                    f"{table_name}",
                ],
            }
        },
    )

    clean_table_task >> create_clean_external_tables_task
    return table_sub_dag


create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

sauron_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sauron-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_SAURON_INTO_DATALAKE_RAW_FILE_PATH,
            "parameters": [ENV, DATALAKE_BUCKET],
        }
    },
    execution_timeout=timedelta(hours=3),
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

file_list = FileService.list_layer_sql_files(SOURCE, "clean", schema)
for file_name in file_list:
    file_name = FileService.remove_file_extension(file_name)
    slugged_file_name = file_name.replace("_", "-")
    clean_table = BaseSubDAG.get_sub_dag_operator(
        dag=dag,
        sub_dag_name=f"load-{schema}-{slugged_file_name}",
        sub_dag_func=build_table_sub_dag,
        env=ENV,
        source=SOURCE,
        schema=schema,
        table_name=file_name,
        main_dag_id=FULL_DAG_ID,
        main_schedule_interval=MAIN_SCHEDULE_INTERVAL,
        main_start_date=MAIN_START_DATE,
    )
    sauron_to_datalake_raw_task >> clean_table >> terminate_cluster_task

create_cluster_task >> sauron_to_datalake_raw_task
