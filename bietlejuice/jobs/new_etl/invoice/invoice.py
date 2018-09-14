import gzip
import io
import json
import time
from StringIO import StringIO

import pandas
import requests
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR


class Invoice(object):
    REGEX_MAPPING = {
        'float': {
            'regex': '(\d+),(\d+)',
            'group': '\g<1>.\g<2>'
        },
        'date': {
            'regex': '(\d{2})/(\d{2})/(\d{4})',
            'group': '\g<3>-\g<2>-\g<1>'
        }
    }

    def __init__(self, bucket, _type, year, month, api_dict):
        self.bucket = bucket
        self.athena_client = AthenaClient(self.bucket)
        self._type = _type
        self.year = year
        self.month = month
        self.api_dict = api_dict

    @logger
    def is_job_finished(self, status_url):
        response = json.loads(self.__request_get(url=status_url))
        return 'process-running.status/success' in response['status']

    @logger
    def request_job_data(self, job_url):
        return self.__request_get(url=job_url)

    def __request_get(self, url):
        job_result = requests.get(
            url=url,
            headers={'jwt-token': self.api_dict['token']}
        )

        return job_result.content.decode('utf-8')

    @logger
    def _request_data(self, endpoint_complement):
        url = '{}/{}'.format(self.api_dict['endpoint'], endpoint_complement)
        _logger.info('m=_request_data, url={}'.format(url))

        return requests.get(
            url=url,
            headers={'jwt-token': self.api_dict['token']}
        )

    @logger
    def wait_for_results(self, status_url):
        while not self.is_job_finished(status_url=status_url):
            time.sleep(self.api_dict['job-waiting-time'])

    @logger(exclude='content')
    def load_content_to_memory_as_csv(self, content):
        memory_content = StringIO(content)
        return pandas.read_csv(memory_content)

    @logger(exclude='data_frame')
    def convert_df_to_json(self, data_frame):
        _logger.info('m=convert_csv_to_json')

        gz_body = io.BytesIO()
        with gzip.GzipFile(fileobj=gz_body, mode='w') as fp:
            for row in data_frame.iterrows():
                fp.write(row[1].to_json().encode('utf-8'))
                fp.write('\n')

        return gz_body

    @logger(exclude='_object')
    def save_into_s3_raw(self, _object, file_path_prefix, raw_table_name):
        year_month = '{}-{}'.format(self.year, self.month)

        _logger.info(
            BaseETL.obj_to_s3(
                obj_io=_object,
                bucket=self.bucket,
                file_path='{}/ym={}/data.gz'.format(file_path_prefix, year_month)
            )
        )

        self.athena_client.upsert_single_partition(
            bucket_folder_path='{}/raw/seubarriga/invoice/{}'.format(self.bucket, self._type),
            database='datalake_raw',
            table=raw_table_name,
            partition_name='ym',
            partition_value=year_month
        )

    @logger
    def _transform_data(self, query, raw_columns, clean_columns, clean_table_name):
        year_month = '{}-{}'.format(self.year, self.month)
        key = 'clean/seubarriga/invoice/{}/ym={}/data.parq'.format(self._type, year_month)

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.format(year_month=year_month),
            raw_columns=raw_columns,
            clean_columns=clean_columns
        )

        self.athena_client.upsert_single_partition(
            bucket_folder_path='{}/clean/seubarriga/invoice/{}'.format(self.bucket, self._type),
            database='datalake_clean',
            table=clean_table_name,
            partition_name='ym',
            partition_value=year_month
        )

    @logger
    def load_into_ods(self):
        query = BaseETL.get_query_from_file_name(
            '{}/invoice/{}_clean_load_ods.sql'.format(DATALAKE_QUERIES_DIR, self._type))

        year_month = '{}-{}'.format(self.year, self.month)
        data_frame = self.athena_client.execute_query_and_return_dataframe(query.format(year_month=year_month))

        _logger.info(
            'm=load_into_ods, _type={}, year_month={}, msg=deleting from ods table'.format(self._type, year_month))
        BaseETL.execute_command(
            command="delete from invoice.{} where ym_partition = '{}'".format(self._type, year_month),
            db_enum=EnumDB.BI_ODS,
            encoding='utf-8',
            commit=True
        )

        _logger.info('m=load_into_ods, _type={}, msg=sending dataframe to ods'.format(self._type))
        BaseETL.dataframe_to_ods(
            df=data_frame,
            table_name='invoice.{}'.format(self._type),
            encoding='utf-8'
        )
