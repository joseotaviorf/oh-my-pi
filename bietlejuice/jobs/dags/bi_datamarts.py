import os
from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.dags import DW_QUERIES_DIR
from bietlejuice.jobs.dags.util import environment as env

# env vars
env.set_airflow_var_to_local_env('BI_DW')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_ID = 'bi-datamarts'
MAIN_START_DATE = datetime(2018, 8, 22)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 9 * * *')

DATAMARTS_SCHEMA = 'datamarts'

logger = QuintoAndarLogger(MAIN_DAG_ID)


# functions
@logger
def create_datamart_from_dw(table_name, **kwargs):
    query = BaseETL.get_query_from_file_name('{}/datamarts/dw/{}.sql'.format(DW_QUERIES_DIR, table_name))

    logger.info('m=create_datamart_from_dw, table_name={}, msg=Dropping table'.format(table_name))
    BaseETL.execute_command(
        command='drop table if exists {}.{}'.format(DATAMARTS_SCHEMA, table_name),
        db_enum=EnumDB.BI_DW,
        encoding='utf-8',
        commit=True
    )

    logger.info('m=create_datamart_from_dw, table_name={}, msg=Creating table'.format(table_name))
    BaseETL.execute_command(
        command='create table {}.{} as ({})'.format(DATAMARTS_SCHEMA, table_name, query.replace(';', '')),
        db_enum=EnumDB.BI_DW,
        encoding='utf-8',
        commit=True
    )


def create_datamart_from_athena(table_name, **kwargs):
    athena = AthenaClient(s3_bucket)
    query = BaseETL.get_query_from_file_name('{}/datamarts/athena/{}.sql'.format(DW_QUERIES_DIR, table_name))

    logger.info('m=create_datamart_from_athena, table_name={}, msg=Dropping table'.format(table_name))
    BaseETL.execute_command(
        command='drop table if exists {}.{}'.format(DATAMARTS_SCHEMA, table_name),
        db_enum=EnumDB.BI_DW,
        encoding='utf-8',
        commit=True
    )

    logger.info('m=create_datamart_from_athena, table_name={}, msg=Reading data'.format(table_name))
    execution_date = kwargs['execution_date'].strftime('%Y-%m-%d')
    df = athena.execute_query_and_return_dataframe(
        sql=query,
        query_params={'dt': execution_date}
    )

    logger.info('m=create_datamart_from_athena, table_name={}, msg=Creating table in datamart'.format(table_name))
    BaseETL.create_table_from_dataframe(
        enum_db=EnumDB.BI_DW,
        df=df,
        table_name='{}.{}'.format(DATAMARTS_SCHEMA, table_name),
        encoding='utf-8',
    )

    logger.info('m=create_datamart_from_athena, table_name={}, msg=Writing data to datamart'.format(table_name))
    BaseETL.dataframe_to_db(
        enum_db=EnumDB.BI_DW,
        df=df,
        table_name='{}.{}'.format(DATAMARTS_SCHEMA, table_name),
        encoding='utf-8',
        append=False,
        bucket_name=s3_bucket
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
# TODO: make it DRY
'''
Gets all files from DW_QUERIES_DIR/datamarts/dw and creates a table using the filename
'''
for filename in os.listdir('{}/{}/dw'.format(DW_QUERIES_DIR, DATAMARTS_SCHEMA)):
    filename_split = filename.split('.')

    if len(filename_split) < 1:
        logger.warn('m=dag_run, filename={}, msg=no file extension'.format(filename))
        continue

    if filename_split[1] != 'sql':
        logger.warn('m=dag_run, filename={}, msg=file extension different from sql'.format(filename))
        continue

    table_name = filename_split[0]
    PythonOperator(
        task_id=table_name,
        provide_context=True,
        python_callable=create_datamart_from_dw,
        dag=main_dag,
        op_kwargs={'table_name': table_name}
    )


'''
Gets all files from DW_QUERIES_DIR/datamarts/athena and creates a table using the filename
'''
for filename in os.listdir('{}/{}/athena'.format(DW_QUERIES_DIR, DATAMARTS_SCHEMA)):
    filename_split = filename.split('.')

    if len(filename_split) < 1:
        logger.warn('m=dag_run, filename={}, msg=no file extension'.format(filename))
        continue

    if filename_split[1] != 'sql':
        logger.warn('m=dag_run, filename={}, msg=file extension different from sql'.format(filename))
        continue

    table_name = filename_split[0]
    PythonOperator(
        task_id=table_name,
        provide_context=True,
        python_callable=create_datamart_from_athena,
        dag=main_dag,
        op_kwargs={'table_name': table_name}
    )
