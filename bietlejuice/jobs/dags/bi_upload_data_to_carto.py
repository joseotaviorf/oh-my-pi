from airflow.models import DAG

from datetime import datetime, timedelta
import json
import petl
import os
import yaml

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.new_base_etl import BaseETL, EnumDB
from bietlejuice.jobs.dags.util import environment as env

from bietlejuice.jobs.wrappers.carto.carto_api import CartoApi

from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient
from bietlejuice.jobs.dags import DATALAKE_QUERIES_DIR, DW_QUERIES_DIR

env.set_airflow_var_to_local_env('BI_DW')
athena = AthenaClient('5a-datalake')
logger = QuintoAndarLogger('bi-doorman-data')
CARTO_PATH = 'carto'
CARTO_CREDENTIALS = json.loads(env.get_airflow_env_var('CARTO_CREDENTIALS'))
carto_api = CartoApi(CARTO_CREDENTIALS)


def load_data_and_upload_to_carto(queries_dir, sql_filename, carto_table_name, db, final_sql, **kwargs):
    file_name = '{}/{}/{}.sql'.format(queries_dir, CARTO_PATH, sql_filename)
    logger.info('m=load_data_and_upload_to_carto, file={}, msg=reading data'.format(file_name))
    query = BaseETL.get_query_from_file_name(file_name)

    if db == 'athena':
        df = athena.execute_query_and_return_dataframe(
            sql=query,
            paginate=False,
            page_size=0)
    elif db == 'dw':
        table = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query=query
        )
        df = petl.todataframe(table)

    csv_file_path = '/var/tmp/{}.csv'.format(sql_filename)
    df.to_csv(csv_file_path, index=False, encoding='utf-8')
    if len(df) > 0:
        # upload csv to carto
        create_table_statement = BaseETL.generate_create_table_statement(df, carto_table_name)
        carto_api.run_sql(create_table_statement)
        carto_api.run_sql('TRUNCATE TABLE {}'.format(carto_table_name))
        carto_api.upload_csv(csv_file_path, carto_table_name)
        carto_api.run_sql("SELECT cdb_cartodbfytable('dev', '{}')".format(carto_table_name))
        if final_sql is not None:
            carto_api.run_sql(final_sql)


MAIN_DAG_NAME = 'bi-upload-data-to-carto'

dag = DAG(
    dag_id=MAIN_DAG_NAME,
    description='Upload data to CARTO',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False,
        'retries': 1,
        'retry_delay': timedelta(minutes=30),
    },
    start_date=datetime(2019, 2, 16, 0, 0, 0),
    schedule_interval='30 9 * * *',
    max_active_runs=1,
    catchup=False
)

# operators
operators = [
    {'queries_dir': DW_QUERIES_DIR, 'db': 'dw'},
    {'queries_dir': DATALAKE_QUERIES_DIR, 'db': 'athena'}
]

tasks = []

for operator in operators:
    '''
    Gets all config files from queries_dir/carto/
    '''
    for file_name in os.listdir('{}/{}'.format(operator['queries_dir'], CARTO_PATH)):
        file_name_split = file_name.split('.')
        table_name = file_name_split[0]
        file_path = '{}/{}/{}'.format(operator['queries_dir'], CARTO_PATH, file_name)
        if file_name.endswith(('.yml', 'yaml')):
            with open(file_path, 'r') as stream:
                config = yaml.safe_load(stream)
                task_dict = {
                    'queries_dir': operator['queries_dir'],
                    'db': operator['db'],
                    'sql_filename': config['sql_filename'],
                    'carto_table_name': config['carto_table_name'],
                    'final_sql': config['final_sql'],
                    'file_name': file_name
                }
                tasks.append(task_dict)


# create tasks
for task in tasks:
    BaseDAG.build_python_operator(
        dag=dag,
        task_id=task['carto_table_name'],
        python_callable=load_data_and_upload_to_carto,
        op_kwargs=task,
        provide_context=True
    )
