import gzip
import io
import json
import os
import time
from StringIO import StringIO

import pandas
import requests

import sys
here = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(here, '../../../'))
from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger


class Invoice(object):
    BUCKET_DATALAKE = os.environ['bi-datalake-s3-bucket']

    SEUBARRIGA_INVOICE = json.loads(os.environ['seubarriga'])['invoice']

    REGEX_DATE = '(\d{2})/(\d{2})/(\d{4})'
    GROUP_DATE = '\g<3>-\g<2>-\g<1>'

    def __init__(self, _type, year, month):
        self.athena_client = AthenaClient(Invoice.BUCKET_DATALAKE)
        self._type = _type
        self.year = year
        self.month = month

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
            headers={'jwt-token': Invoice.SEUBARRIGA_INVOICE['token']}
        )

        return job_result.content.decode('utf-8')

    @logger
    def wait_for_results(self, status_url):
        while not self.is_job_finished(status_url=status_url):
            time.sleep(Invoice.SEUBARRIGA_INVOICE['job-waiting-time'])

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

    @logger(exclude='object')
    def save_into_s3_raw(self, object, file_path_prefix, raw_table_name):
        _logger.info(
            BaseETL.obj_to_s3(
                obj_io=object,
                bucket=Invoice.BUCKET_DATALAKE,
                file_path='{0}/ym={2}-{3}/data.gz'.format(file_path_prefix, self._type, self.year, self.month)
            )
        )

        self.athena_client.upsert_single_partition(
            bucket_folder_path='{}/raw/seubarriga/invoice/{}'.format(Invoice.BUCKET_DATALAKE, self._type),
            database='datalake_raw',
            table=raw_table_name,
            partition_name='ym',
            partition_value='{}-{}'.format(self.year, self.month)
        )

    @logger
    def transform_data(self, query, raw_columns, clean_columns, clean_table_name):
        key = 'clean/seubarriga/invoice/{0}/ym={1}-{2}/data.gz'.format(self._type, self.year, self.month)
        self.athena_client.create_parquet_from_query(
            key=key,
            query=query,
            raw_columns=raw_columns,
            clean_columns=clean_columns
        )

        self.athena_client.upsert_single_partition(
            bucket_folder_path='{}/clean/seubarriga/invoice/{}'.format(Invoice.BUCKET_DATALAKE, self._type),
            database='datalake_clean',
            table=clean_table_name,
            partition_name='ym',
            partition_value='{}-{}'.format(self.year, self.month)
        )

    @logger
    def load_into_ods(self, query, ods_table):
        data_frame = self.athena_client.execute_query_and_return_dataframe(query)
        BaseETL.execute_command(
            command="delete from invoice.{0} where year_month = '{1}-{2}'".format(ods_table, self.year, self.month),
            db_enum=EnumDb.BI_ODS,
            encoding='utf-8',
            commit=True
        )

        BaseETL.dataframe_to_ods(
            df=data_frame,
            table_name='invoice.{}'.format(ods_table),
            encoding='utf-8'
        )
