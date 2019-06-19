import os
from datetime import datetime
import yaml

from airflow.models import DAG
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.dags import DW_QUERIES_DIR
from bietlejuice.jobs.dags import DATALAKE_QUERIES_DIR
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
    query = BaseETL.get_query_from_file_name('{}/{}/{}.sql'.format(DW_QUERIES_DIR, DATAMARTS_SCHEMA, table_name))

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
    query = BaseETL.get_query_from_file_name('{}/{}/{}.sql'.format(DATALAKE_QUERIES_DIR, DATAMARTS_SCHEMA, table_name))

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
        append=False
    )


def create_task(dag, queries_dir, python_callable, db, table_name, file_name):
    task = BaseDAG.build_python_operator(
        dag=dag,
        task_id='{}_{}'.format(db, table_name),
        provide_context=True,
        python_callable=python_callable,
        op_kwargs={'table_name': table_name}
    )


def config_task(dag, queries_dir, python_callable, db, table_name, file_name):
    task_id = '{}_{}'.format(db, table_name)
    current_task = dag.task_dict[task_id]
    file_path = '{}/{}/{}'.format(queries_dir, DATAMARTS_SCHEMA, file_name)
    with open(file_path, 'r') as stream:
        config = yaml.safe_load(stream)
        streams = config['streams']
        for stream in streams:
            direction = stream['direction']
            task_ids = stream['task_ids']
            set_stream_method = getattr(current_task, 'set_{}'.format(direction))
            for id in task_ids:
                logger.info('m=config_task, msg=setting {} {} of {}'.format(task_id, direction, id))
                set_stream_method(dag.task_dict[id])


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
operators = [
    {'queries_dir': DW_QUERIES_DIR, 'python_callable': create_datamart_from_dw, 'db': 'dw'},
    {'queries_dir': DATALAKE_QUERIES_DIR, 'python_callable': create_datamart_from_athena, 'db': 'athena'}
]

queries = []
task_configs = []

for operator in operators:
    '''
    Gets all queries and config files from queries_dir/datamarts/
    '''
    for file_name in os.listdir('{}/{}'.format(operator['queries_dir'], DATAMARTS_SCHEMA)):
        file_name_split = file_name.split('.')
        table_name = file_name_split[0]
        file_dict = {
            'queries_dir': operator['queries_dir'],
            'python_callable': operator['python_callable'],
            'db': operator['db'],
            'table_name': table_name,
            'file_name': file_name
        }
        if file_name.endswith('.sql'):
            queries.append(file_dict)
        elif file_name.endswith(('.yml', 'yaml')):
            task_configs.append(file_dict)

# create tasks
for query in queries:
    create_task(
        dag=main_dag,
        queries_dir=query['queries_dir'],
        python_callable=query['python_callable'],
        db=query['db'],
        table_name=query['table_name'],
        file_name=query['file_name']
    )

# configure tasks
for task_config in task_configs:
    config_task(
        dag=main_dag,
        queries_dir=task_config['queries_dir'],
        python_callable=task_config['python_callable'],
        db=task_config['db'],
        table_name=task_config['table_name'],
        file_name=task_config['file_name']
    )
