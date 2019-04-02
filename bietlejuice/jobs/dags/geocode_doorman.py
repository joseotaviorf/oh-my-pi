# coding=utf-8
from airflow.models import DAG
from datetime import datetime, timedelta

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env

from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient
from bietlejuice.jobs.dags import DATALAKE_QUERIES_DIR

import pandas as pd
from bietlejuice.jobs.wrappers.geocoding.geocoding_api import GEOCODING_API

env.set_airflow_var_to_local_env('BI_DW')
athena = AthenaClient('5a-datalake')
logger = QuintoAndarLogger('bi-doorman-data')


def read_query(file_name):
    with open(file_name) as f:
        return f.read()


def load_doorman(**kwargs):
    sql_filename = 'extract_doorman_address'
    file_name = '{}/{}.sql'.format(DATALAKE_QUERIES_DIR, sql_filename)
    logger.info("Reading from S3: {} file:{}".format(datetime.utcnow(), file_name))
    query = read_query(file_name)
    execution_date = datetime.utcnow().strftime('%Y-%m-%d')
    df = athena.execute_query_and_return_dataframe(
        sql=query,
        paginate=False,
        page_size=0,
        query_params={'dt': execution_date})
    return df


def geocode_doorman(**kwargs):
    df_door = load_doorman()
    if len(df_door) == 0:
        print('--->no doorman loaded. Interrupting task.')
    else:
        # this looks useless but it is not, it acutally fixes python 2 stupid encoding issues
        df_door.to_csv('/var/tmp/df_door.csv', index=False, encoding='utf-8')
        df_door = pd.read_csv('/var/tmp/df_door.csv', encoding='utf-8')
        if len(df_door) > 0:
            date_formatted = datetime.now().strftime('%Y-%m-%d-%H-%M-%S')
            data_folder = '/var/tmp/{}_geocode_doorman/'.format(date_formatted)
            df_address = df_door[(df_door.formatted_address.notna()) & (df_door.google_formatted_address.isna())].drop('google_formatted_address', axis=1)
            geocoding_api = GEOCODING_API()
            df_door_geocoded = geocoding_api.geocode(df=df_address, address_col='formatted_address', data_folder=data_folder)
            if isinstance(df_door_geocoded, pd.DataFrame):
                cols = ['id_user_doorman', 'geocode_hash', 'google_formatted_address', 'lat', 'lng', 'location_type', 'place_id', 'types']
                df_export = df_door_geocoded[df_door_geocoded.google_formatted_address.notna()][cols]
                df_export.to_csv('/var/tmp/geocoded_doorman_export.csv', index=False, encoding='utf-8')
                # write results to S3
                df_export[cols] = df_export[cols].astype(str)
                key = 'raw/external/doorman_geocoded_addresses/{}_doorman_geocoded_addresses.parq'.format(date_formatted)
                athena.create_parquet_from_df(key=key, df=df_export)
            else:
                print('---> no addresses to geocode.')
        else:
            print('---> no addresses to geocode.')


dag = DAG(
    dag_id='geocode-doorman',
    description='Geocode doorman',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False,
        'retries': 1,
        'retry_delay': timedelta(minutes=30),
    },
    start_date=datetime(2019, 2, 16, 0, 0, 0),
    schedule_interval='0 9 * * *',
    max_active_runs=1
)

# operators
geocode_doorman_dag = BaseDAG.build_python_operator(
    dag=dag,
    task_id='geocode_doorman',
    python_callable=geocode_doorman,
    provide_context=True
)
