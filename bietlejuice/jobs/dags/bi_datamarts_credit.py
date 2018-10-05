import os
from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.dags import DATAMART_CREDIT_QUERIES_DIR
from bietlejuice.jobs.dags.util import environment as env

# env vars
env.set_airflow_var_to_local_env('BI_DW')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_ID = 'bi-datamarts-credit'
MAIN_START_DATE = datetime(2018, 10, 4)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 9 * * *')

logger = QuintoAndarLogger(MAIN_DAG_ID)


# functions


@logger
def create_datamart(table_name, **kwargs):
    """
    """
    schema = "datamarts_credit"
    query = BaseETL.get_query_from_file_name('{}/{}.sql'.format(DATAMART_CREDIT_QUERIES_DIR, table_name))

    logger.info("m=create_datamart, table_name={}, msg=Dropping table".format(table_name))
    BaseETL.execute_command(
        command='drop table if exists {}.{}'.format(schema, table_name),
        db_enum=EnumDB.BI_DW,
        encoding='utf-8',
        commit=True
    )

    logger.info("m=create_datamart, table_name={}, msg=Creating table".format(table_name))
    BaseETL.execute_command(
        command='create table {}.{} as ({})'.format(schema, table_name, query),
        db_enum=EnumDB.BI_DW,
        encoding='utf-8',
        commit=True
    )


# dags
main_dag = DAG(
    dag_id=MAIN_DAG_ID,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=False
)

# operators

for filename in os.listdir(DATAMART_CREDIT_QUERIES_DIR):

    filename_split = filename.split(".")

    if len(filename_split) < 1:
        logger.warn("m=dag_run, filename={}, msg=no file extension".format(filename))
        continue

    if filename_split[1] != "sql":
        logger.warn("m=dag_run, filename={}, msg=file extension different from sql".format(filename))
        continue

    table_name = filename_split[0]

    PythonOperator(
        task_id=table_name,
        provide_context=True,
        python_callable=create_datamart,
        dag=main_dag,
        op_kwargs={'table_name': table_name}
    )

# flow


# TODO: add unit tests
