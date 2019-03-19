# coding=utf-8
import urllib
import requests
import pandas as pd
import gzip
import json

from bietlejuice.jobs.dags.util import environment as env

# FIXME: add variables to airflow
CARTO_CREDENTIALS = json.loads(env.get_airflow_env_var('CARTO_CREDENTIALS'))
CARTO_API_KEY = CARTO_CREDENTIALS['api_key']
BASE_URL = CARTO_CREDENTIALS['base_url']
BASE_URL_SQL = BASE_URL + 'sql'
BASE_URL_COPY = BASE_URL + 'sql/copyfrom'


class CARTO_API(object):
    def __init__(self, *args, **kwargs):
        pass

    @staticmethod
    def run_sql(sql, data_format='JSON'):
        url_params_encoded = urllib.pathname2url(sql)
        url = '{}?q={}&api_key={}&format={}'.format(BASE_URL_SQL, url_params_encoded, CARTO_API_KEY, data_format)
        r = requests.get(url)
        return r.content

    @staticmethod
    def upload_csv(csv_file_path, table_name):
        df = pd.read_csv(csv_file_path)
        cols = ','.join(df.columns.values.tolist())
        gzip_file_path = csv_file_path + '.gz'
        with open(csv_file_path, 'rb') as f_in, gzip.open(gzip_file_path, 'wb') as f_out:
            f_out.writelines(f_in)
        sql = 'COPY {} ({}) FROM stdin WITH (FORMAT csv, HEADER true)'.format(table_name, cols)
        url_params_encoded = urllib.pathname2url(sql)
        url = '{}?q={}&api_key={}'.format(BASE_URL_COPY, url_params_encoded, CARTO_API_KEY)
        headers = {
            'Content-Encoding': 'gzip',
            'Content-Type': 'application/octet-stream'
        }
        data = open(gzip_file_path, 'rb').read()
        r = requests.post(url, data=data, headers=headers)
        return r.content
