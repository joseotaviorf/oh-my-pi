import pandas as pd

from airflow.models import DAG
from datetime import datetime, timedelta

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env

from bietlejuice.jobs.wrappers.carto.carto_api import CartoApi
from bietlejuice.jobs.wrappers.geocoding.geocoding_api import GeocodingApi

from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient
from bietlejuice.jobs.dags import DATALAKE_QUERIES_DIR

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
            geocoding_api = GeocodingApi()
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


def load_data_and_upload_to_carto(sql_filename, carto_table_name, execution_date, final_sql):
    file_name = '{}/{}.sql'.format(DATALAKE_QUERIES_DIR, sql_filename)
    logger.info("Reading from S3: {} file:{}".format(datetime.utcnow(), file_name))
    query = read_query(file_name)

    df = athena.execute_query_and_return_dataframe(
        sql=query,
        paginate=False,
        page_size=0,
        query_params={'dt': execution_date})

    csv_file_path = '/var/tmp/{}.csv'.format(sql_filename)
    df.to_csv(csv_file_path, index=False, encoding='utf-8')
    if len(df) > 0:
        # upload CSV to CARTO
        print(CartoApi.run_sql('TRUNCATE TABLE {}'.format(carto_table_name)))
        print(CartoApi.upload_csv(csv_file_path, carto_table_name))
        print(CartoApi.run_sql(final_sql))
        # write result to S3
        df_export = df
        cols = df_export.columns.values.tolist()
        df_export[cols] = df_export[cols].astype(str)
        key = 'clean/external/{}/{}.parq'.format(carto_table_name, carto_table_name)
        athena.create_parquet_from_df(key=key, df=df_export)


def load_building_doorman_data_iptu_sp(**kwargs):
    carto_table_name = 'iptu_bldgs_doormen_data'
    load_data_and_upload_to_carto(
        sql_filename='building_join_doorman',
        carto_table_name=carto_table_name,
        execution_date=kwargs['execution_date'].strftime('%Y-%m-%d'),
        final_sql='UPDATE {} SET the_geom = ST_SetSRID(ST_MakePoint(lng, lat), 4326) WHERE the_geom IS NULL'.format(carto_table_name)
    )


def load_building_doorman_data_cnpj(**kwargs):
    carto_table_name = 'cnpj_bldgs_doormen_data'
    load_data_and_upload_to_carto(
        sql_filename='cnpj_condo_join_doorman',
        carto_table_name=carto_table_name,
        execution_date=kwargs['execution_date'].strftime('%Y-%m-%d'),
        final_sql='UPDATE {} SET the_geom = ST_SetSRID(ST_MakePoint(lng, lat), 4326) WHERE the_geom IS NULL'.format(carto_table_name)
    )


def load_region_polygons(**kwargs):
    carto_table_name = 'qa_subregions'
    load_data_and_upload_to_carto(
        sql_filename='extract_region_polygons',
        carto_table_name=carto_table_name,
        execution_date=kwargs['execution_date'].strftime('%Y-%m-%d'),
        final_sql='UPDATE {} SET the_geom = ST_GeomFromText(geometry, 4326)'.format(carto_table_name)
    )


dag = DAG(
    dag_id='join-buildings-to-doorman',
    description='Geocode doorman, join buildings to doorman and upload data to CARTO',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False,
        'retries': 1,
        'retry_delay': timedelta(minutes=30),
    },
    start_date=datetime(2019, 2, 16, 0, 0, 0),
    schedule_interval='30 9 * * *',
    max_active_runs=1
)

# operators
geocode_doorman_dag = BaseDAG.build_python_operator(
    dag=dag,
    task_id='geocode_doorman',
    python_callable=geocode_doorman,
    provide_context=True
)

building_doorman_data_iptu_sp = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_building_doorman_data_iptu_sp',
    python_callable=load_building_doorman_data_iptu_sp,
    provide_context=True
)

building_doorman_data_cnpj = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_building_doorman_data_cnpj',
    python_callable=load_building_doorman_data_cnpj,
    provide_context=True
)

regions_data = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_region_polygons',
    python_callable=load_region_polygons,
    provide_context=True
)

# flow
geocode_doorman_dag >> building_doorman_data_iptu_sp >> building_doorman_data_cnpj >> regions_data
