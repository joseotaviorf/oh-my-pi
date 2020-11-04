from airflow.models import DAG

from datetime import datetime, timedelta
import json
import petl
import os
import yaml

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.new_base_etl import BaseETL, EnumDB
from bietlejuice.jobs.dags.util import environment as env

from bietlejuice.jobs.wrappers.carto import CartoApi

from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient
from bietlejuice.jobs.dags import DATALAKE_QUERIES_DIR, DW_QUERIES_DIR

env.set_airflow_var_to_local_env('BI_DW', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')
bucket = env.get_airflow_env_var("bi-datalake-s3-bucket")
data_acc_aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
data_acc_aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')
athena = AthenaClient(bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)
logger = QuintoAndarLogger('bi-upload-data-to-carto')
CARTO_PATH = 'carto'
CARTO_CREDENTIALS = json.loads(env.get_airflow_env_var('CARTO_CREDENTIALS'))
carto_api = CartoApi(CARTO_CREDENTIALS)


def load_data_and_upload_to_carto(query_dir, sql_filename, carto_table_name, db, final_sql, **kwargs):
    file_name = '{}/{}/{}.sql'.format(query_dir, CARTO_PATH, sql_filename)
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
        # upload file to carto
        carto_api.import_file(csv_file_path, 'overwrite')
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
        'retry_delay': timedelta(minutes=3),
    },
    start_date=datetime(2019, 9, 7, 0, 0, 0),
    schedule_interval='30 9 * * *',
    max_active_runs=1,
    concurrency=3,
    catchup=False
)

# query_directories
query_directories = [
    {'query_dir': DW_QUERIES_DIR, 'db': 'dw'},
    {'query_dir': DATALAKE_QUERIES_DIR, 'db': 'athena'}
]

tasks = []

for dir in query_directories:
    '''
    Gets all config files from query_dir/carto/
    '''
    for file_name in os.listdir('{}/{}'.format(dir['query_dir'], CARTO_PATH)):
        file_name_split = file_name.split('.')
        table_name = file_name_split[0]
        file_path = '{}/{}/{}'.format(dir['query_dir'], CARTO_PATH, file_name)
        if file_name.endswith(('.yml', 'yaml')):
            with open(file_path, 'r') as stream:
                config = yaml.safe_load(stream)
                task_dict = {
                    'query_dir': dir['query_dir'],
                    'db': dir['db'],
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
        provide_context=True,
        execution_timeout=timedelta(hours=1)
    )
