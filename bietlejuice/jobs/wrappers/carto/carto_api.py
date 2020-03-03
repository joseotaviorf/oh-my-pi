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
        self.ASYNC_CALLS_WAIT_TIME = 3
        self.RUN_SQL_STATUSES = {'success': ['done'],
                                 'failed': ['failed', 'canceled', 'unknown'],
                                 'running': ['pending', 'running', 'not started']}
        self.IMPORT_FILE_STATUSES = {'success': ['complete'],
                                     'failed': ['failure'],
                                     'running': ['enqueued', 'pending', 'uploading',
                                                 'unpacking', 'importing', 'guessing',
                                                 'not started']}

    @logger
    def run_sql_sync(self, sql, data_format='JSON'):
        url_params_encoded = urllib.pathname2url(sql)
        url = '{}?q={}&api_key={}&format={}'.format(self.BASE_URL + 'v2/sql', url_params_encoded, self.CARTO_API_KEY, data_format)
        try:
            response = requests.get(url)
        except Exception as e:
            raise ValueError('m=run_sql_sync, msg=error running SQL on CARTO, sql={}, e={}'.format(sql, e))
        logger.info('m=run_sql_sync, msg=CARTO API responded, response={}'.format(response.content))
        response_json = json.loads(response.content)
        if u'error' in response_json:
            raise ValueError('m=run_sql_sync, msg=error running SQL on CARTO, e={}'.format(response_json[u'error']))

    @logger
    def run_sql(self, sql, data_format='JSON'):
        """Runs SQL asynchronously in CARTO. See docs at https://carto.com/developers/sql-api/guides/batch-queries/
        """
        url = '{}?api_key={}'.format(self.BASE_URL + 'v2/sql/job', self.CARTO_API_KEY)
        data = json.dumps({'query': sql})
        post_response = requests.post(url, headers={'Content-Type': 'application/json'}, data=data)
        post_response_json = json.loads(post_response.content)
        status_url = '{}/{}?api_key={}'.format(self.BASE_URL + 'v2/sql/job', post_response_json['job_id'], self.CARTO_API_KEY)
        response_status = 'not started'
        while response_status in self.RUN_SQL_STATUSES['running']:
            response = requests.get(status_url)
            status_response_json = json.loads(response.content)
            response_status = status_response_json['status']
            if response_status in self.RUN_SQL_STATUSES['running']:
                time.sleep(self.ASYNC_CALLS_WAIT_TIME)
        logger.info('m=run_sql, msg=CARTO API responded, response={}'.format(response.content))
        if response_status not in self.RUN_SQL_STATUSES['success']:
            raise ValueError(('m=run_sql, msg=error running SQL on CARTO, API returned an error, sql={}, e={}'.format(sql, status_response_json)))

    @logger
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
        try:
            response = requests.post(url, data=data, headers=headers)
        except Exception as e:
            raise ValueError('m=upload_csv, msg=error uploding CSV to CARTO, table={}, e={}'.format(table_name, e))
        logger.info('m=upload_csv, msg=CARTO API responded, response={}'.format(response.content))
        response_json = json.loads(response.content)
        if u'error' in response_json:
            raise ValueError('m=upload_csv, msg=error uploding CSV to CARTO, table={}, e={}'.format(table_name, response_json[u'error']))

    @logger
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
        response_state = 'not started'
        while response_state in self.RUN_SQL_STATUSES['running']:
            response = requests.get(status_url)
            status_response_json = json.loads(response.content)
            response_state = status_response_json['state']
            if response_state in self.IMPORT_FILE_STATUSES['running']:
                time.sleep(self.ASYNC_CALLS_WAIT_TIME)
        if response_state not in self.IMPORT_FILE_STATUSES['success']:
            raise ValueError('m=import_file, msg=error importing file to CARTO, file={}, e={}'.format(file_path, status_response_json))
