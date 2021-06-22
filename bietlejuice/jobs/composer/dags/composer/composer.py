from datetime import datetime

import airflow.utils.helpers as airflow_helpers
import pendulum
import os
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_athena import (
    QuintoAndarCreateAthenaExternalTableOperator,
)
from airflow.operators.quintoandar_transfer_data import QuintoAndarMySqlToS3Operator

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG
from bietlejuice.jobs.composer.base.db import DATALAKE_SQL_DIR
from bietlejuice.jobs.composer.base.pipeline import (
    EnvironmentEnum,
)  # TODO Create an Airflow environment enum and use here (instead of using Spark code)
from bietlejuice.jobs.composer.services import FileService

DAG_NAME = "composer"
DAG_ID = f"bietlejuice.{DAG_NAME}"

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 8, 21, 0, 0, 0, tzinfo=LOCAL_TZ)
SCHEDULE_INTERVAL = "*/15 6-18 * * *"

ENV = os.environ.get("ENVIRONMENT")
S3_BUCKET = Variable.get("datalake_bucket")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
)


def move_data_subdag(subdag_name, table_name):
    local_dag = BaseSubDAG(
        sub_dag_name=subdag_name,
        dag_name=DAG_ID,
        schedule_interval=SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    move_data_to_datalake_task = QuintoAndarMySqlToS3Operator(
        dag=local_dag,
        table=table_name,
        task_id="move-data-to-datalake",
        bucket=S3_BUCKET,
        filename="data.json",
        s3_file_path="raw/composer/{}".format(table_name),
        mysql_conn_id="airflow_db",
    )

    if ENV == EnvironmentEnum.FORNO:
        schema_suffix = ""
    else:
        schema_suffix = f"_{ENV}"
    database = f"datalake_composer_raw{schema_suffix}"

    ddl_query_raw = FileService.get_query_from_file_name(
        "{}/ddl/raw/composer/{}.ddl".format(DATALAKE_SQL_DIR, table_name)
    ).format(BUCKET=S3_BUCKET, DATABASE=database)
    create_athena_raw_table_task = QuintoAndarCreateAthenaExternalTableOperator(
        dag=local_dag,
        task_id="create-athena-raw-table",
        database=database,
        table=table_name,
        ddl_query=ddl_query_raw,
        output_location="s3://{}/query_results/".format(S3_BUCKET),
    )

    airflow_helpers.chain(move_data_to_datalake_task, create_athena_raw_table_task)

    return local_dag


dag_table_subdag = BaseSubDAG.get_sub_dag_operator(
    dag=dag, sub_dag_name="dag", sub_dag_func=move_data_subdag, table_name="dag"
)
dag_run_table_subdag = BaseSubDAG.get_sub_dag_operator(
    dag=dag, sub_dag_name="dag_run", sub_dag_func=move_data_subdag, table_name="dag_run"
)
task_fail_subdag = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="task_fail",
    sub_dag_func=move_data_subdag,
    table_name="task_fail",
)
