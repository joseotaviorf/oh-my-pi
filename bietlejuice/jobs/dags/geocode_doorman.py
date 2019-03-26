# coding=utf-8
import pandas as pd
import geopy
import json
from pandas.io.json import json_normalize
import glob
import os
from pathlib import Path
import hashlib

from airflow.models import DAG
from datetime import datetime, timedelta

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env

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


def load_geocoded_addresses(path_to_folder):
    json_files = glob.glob(path_to_folder + '*.json')
    frames = []
    for f in json_files:
        e = json.load(open(f))
        filename = os.path.splitext(os.path.basename(f))[0]
        e['filename'] = filename
        e_df = pd.DataFrame.from_dict(json_normalize(e))
        frames.append(e_df)
    geocoded_data = pd.concat(frames, sort=True)
    return geocoded_data


def join_geocoded_addresses_to_df(df, geocoded_data):
    cols = ['geocode_hash', 'formatted_address', 'geometry.location.lat', 'geometry.location.lng', 'geometry.location_type', 'place_id', 'types']
    df_geo = df.merge(geocoded_data[cols], how='left', on='geocode_hash')
    df_geo.rename(columns={'geometry.location.lat': 'lat', 'geometry.location.lng': 'lng', 'geometry.location_type': 'location_type', 'formatted_address': 'google_formatted_address'}, inplace=True)
    return df_geo


def geocode_addresses(addresses, address_col, id_col, folder_path, geopy_geocoder):
    i = 0
    addresses.is_copy = False  # to stop SettingWithCopyWarning
    print('--->geocoding ' + str(len(addresses)) + ' addresses.')
    for index, row in addresses.iterrows():
        i += 1
        address = row[address_col]
        pkey = str(row[id_col])
        # print(pkey)
        file = Path(folder_path + pkey + ".json")
        if file.exists():
            pass
            # print('--->file already exists, skipping')
        else:
            print(str(i) + '/' + str(len(addresses)) + ' || ' + pkey + ': ', address)
            print('--->making API request')
            try:
                geocoded = geopy_geocoder.geocode(query=address)
                addresses.loc[index, address_col] = address
                addresses.loc[index, id_col] = pkey
                geocoded.raw[address_col] = address
                geocoded.raw[id_col] = pkey
                addresses.loc[index, 'latitude'] = geocoded.latitude
                addresses.loc[index, 'longitude'] = geocoded.longitude
                addresses.loc[index, 'address_geocoded'] = geocoded.address
                if 'plus_code' in geocoded.raw:
                    addresses.loc[index, 'global_plus_code'] = geocoded.raw['plus_code']['global_code']
                if 'place_id' in geocoded.raw:
                    addresses.loc[index, 'google_place_id'] = geocoded.raw['place_id']
                addresses.loc[index, 'raw_geocoded'] = json.dumps(geocoded.raw)
                with open(folder_path + pkey + '.json', 'w') as fp:
                    json.dump(geocoded.raw, fp)
            except Exception as e:
                print(e)
    print('--->done.')


def geocode_doorman(**kwargs):
    df_door = load_doorman()
    if len(df_door) == 0:
        print('--->no doorman loaded. Interrupting task.')
    else:
        df_door.to_csv('tmp/df_door.csv', index=False, encoding='utf-8')
        df_door = pd.read_csv('tmp/df_door.csv', encoding='utf-8')
        # drop null
        df_door = df_door[df_door.formatted_address.notna()]
        # df_door['formatted_address'] = df_door['formatted_address'].str.encode('utf-8')
        # format address to reduce need for geocoding
        df_door['geocode'] = df_door.formatted_address.str.upper().str.encode('utf-8')
        # generate hash for file name and joins
        df_door['geocode_hash'] = df_door['geocode'].apply(lambda x: hashlib.sha1(x.encode('utf-8')).hexdigest())
        # FIXME: will eventually be all cities
        df_door = df_door[df_door['work_city'].str.encode('utf-8').isin(['São Paulo', 'Santo André', 'São Bernardo do Campo', 'São Bernardo', 'São Caetano do Sul', 'São Caetano', 'Rio de Janeiro'])]
        df_address = df_door[df_door.geocode.notna()][['geocode', 'geocode_hash']]
        df_address = df_address.drop_duplicates('geocode')
        # FIXME: load from S3 here
        data_folder = 'tmp/geocode_doorman/'
        # geocode
        # FIXME: add variables to airflow
        GOOGLE_MAPS_API_KEY = env.get_airflow_env_var('GOOGLE_MAPS_API_KEY')
        geopy_geocoder = geopy.geocoders.GoogleV3(api_key=GOOGLE_MAPS_API_KEY, timeout=20)
        geocode_addresses(df_address, 'geocode', 'geocode_hash', data_folder, geopy_geocoder)
        df_geocoded_data = load_geocoded_addresses(data_folder)
        df_address_geocoded = join_geocoded_addresses_to_df(df_address, df_geocoded_data)
        df_door_geocoded = df_door.merge(df_address_geocoded.drop('geocode', axis=1), how='left', on='geocode_hash')
        cols = ['id_user_doorman', 'geocode_hash', 'google_formatted_address', 'lat', 'lng', 'location_type', 'place_id', 'types']
        df_export = df_door_geocoded[df_door_geocoded.google_formatted_address.notna()][cols]
        df_export.to_csv('tmp/geocoded_doorman.csv', index=False, encoding='utf-8')
        # write results to S3
        df_export[cols] = df_export[cols].astype(str)
        key = 'raw/external/doorman_geocoded_addresses/doorman_geocoded_addresses.parq'
        athena.create_parquet_from_df(key=key, df=df_export)


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
