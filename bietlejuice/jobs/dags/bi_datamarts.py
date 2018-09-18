import os
from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from qa_python_utils.default_logger import _logger, logger

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


# functions
@logger
def create_datamart(table_name, **kwargs):
    query = BaseETL.get_query_from_file_name('{}/datamarts/{}.sql'.format(DW_QUERIES_DIR, table_name))

    _logger.info('m=create_datamart, table_name={}, msg=Dropping table'.format(table_name))
    BaseETL.execute_command(
        command='drop table if exists {}.{}'.format(DATAMARTS_SCHEMA, table_name),
        db_enum=EnumDB.BI_DW,
        encoding='utf-8',
        commit=True
    )

    _logger.info('m=create_datamart, table_name={}, msg=Creating table'.format(table_name))
    BaseETL.execute_command(
        command='create table {}.{} as ({})'.format(DATAMARTS_SCHEMA, table_name, query),
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
'''
Gets all files from DW_QUERIES_DIR/datamarts and creates a table using the filename
'''
for filename in os.listdir('{}/{}'.format(DW_QUERIES_DIR, DATAMARTS_SCHEMA)):
    filename_split = filename.split('.')

    if len(filename_split) < 1:
        _logger.warn('m=dag_run, filename={}, msg=no file extension'.format(filename))
        continue

    if filename_split[1] != 'sql':
        _logger.warn('m=dag_run, filename={}, msg=file extension different from sql'.format(filename))
        continue

    table_name = filename_split[0]
    PythonOperator(
        task_id=table_name,
        provide_context=True,
        python_callable=create_datamart,
        dag=main_dag,
        op_kwargs={'table_name': table_name}
    )
