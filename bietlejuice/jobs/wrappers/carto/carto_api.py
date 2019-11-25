import urllib
import requests
import pandas as pd
import gzip
import json
import time

from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('bi-doorman-data')


class CartoApi(object):
    def __init__(self, credentials_json):
        self.CARTO_CREDENTIALS = credentials_json
        self.CARTO_API_KEY = self.CARTO_CREDENTIALS['api_key']
        self.BASE_URL = self.CARTO_CREDENTIALS['base_url']

    def run_sql(self, sql, data_format='JSON'):
        url_params_encoded = urllib.pathname2url(sql)
        url = '{}?q={}&api_key={}&format={}'.format(self.BASE_URL + 'v2/sql', url_params_encoded, self.CARTO_API_KEY, data_format)
        logger.info('m=run_sql, msg=running SQL on CARTO, sql={}'.format(sql))
        try:
            response = requests.get(url)
        except Exception as e:
            logger.error('m=run_sql, msg=error running SQL on CARTO, sql={}, e={}'.format(sql, e))
            raise ValueError(e)
        logger.info('m=run_sql, msg=CARTO API responded, response={}'.format(response.content))
        response_json = json.loads(response.content)
        if u'error' in response_json:
            logger.error('m=run_sql, msg=error running SQL on CARTO, e={}'.format(response_json[u'error']))
            raise ValueError(response_json[u'error'])

    def upload_csv(self, csv_file_path, table_name):
        df = pd.read_csv(csv_file_path)
        cols = ','.join(df.columns.values.tolist())
        gzip_file_path = csv_file_path + '.gz'
        with open(csv_file_path, 'rb') as f_in, gzip.open(gzip_file_path, 'wb') as f_out:
            f_out.writelines(f_in)
        sql = 'COPY {} ({}) FROM stdin WITH (FORMAT csv, HEADER true)'.format(table_name, cols)
        url_params_encoded = urllib.pathname2url(sql)
        url = '{}?q={}&api_key={}'.format(self.BASE_URL + 'v2/sql/copyfrom', url_params_encoded, self.CARTO_API_KEY)
        headers = {
            'Content-Encoding': 'gzip',
            'Content-Type': 'application/octet-stream'
        }
        data = open(gzip_file_path, 'rb').read()
        logger.info('m=upload_csv, msg=uploading CSV to CARTO, table={}'.format(table_name))
        try:
            response = requests.post(url, data=data, headers=headers)
        except Exception as e:
            logger.error('m=upload_csv, msg=error uploding CSV to CARTO, table={}, e={}'.format(table_name, e))
            raise ValueError(e)
        logger.info('m=upload_csv, msg=CARTO API responded, response={}'.format(response.content))
        response_json = json.loads(response.content)
        if u'error' in response_json:
            logger.error('m=upload_csv, msg=error uploding CSV to CARTO, table={}, e={}'.format(table_name, response_json[u'error']))
            raise ValueError(response_json[u'error'])

    def import_file(self, file_path, collision_strategy='overwrite'):
        """Imports a file into CARTO using the Import API (http://carto.com/developers/import-api/guides/quickstart/).
        Preferable to the upload_csv method as it doesn't require dropping the table every time, thus
        preserving access permissions and displaying correctly in the CARTO interface.
        """
        url = '{}?type_guessing=false&quoted_fields_guessing=false&collision_strategy={}&api_key={}'.format(self.BASE_URL + 'v1/imports/', collision_strategy, self.CARTO_API_KEY)
        gzip_file_path = file_path + '.gz'
        with open(file_path, 'rb') as f_in, gzip.open(gzip_file_path, 'wb') as f_out:
            f_out.writelines(f_in)
        file = open(gzip_file_path, 'rb')
        response = requests.post(url, files={'file': file})
        post_response_json = json.loads(response.content)
        status_url = '{}{}?api_key={}'.format(self.BASE_URL + 'v1/imports/', post_response_json['item_queue_id'], self.CARTO_API_KEY)
        final_responses = ['complete', 'failure']
        response_state = None
        while response_state not in final_responses:
            response = requests.get(status_url)
            status_response_json = json.loads(response.content)
            response_state = status_response_json['state']
            if response_state not in final_responses:
                time.sleep(3)
        if response_state == 'failure':
            logger.error('m=import_file, msg=error importing file to CARTO, file={}, e={}'.format(file_path, status_response_json))
            raise ValueError(status_response_json)
