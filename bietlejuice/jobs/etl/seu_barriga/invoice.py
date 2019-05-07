import json
import time

import requests
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL

logger = QuintoAndarLogger('Invoice')


class SeuBarrigaInvoice(object):
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

    def __init__(self, s3_bucket, type_, year, month, api_dict):
        self.s3_bucket = s3_bucket
        self.athena_client = AthenaClient(self.s3_bucket)
        self.type_ = type_
        self.year = year
        self.month = month
        self.year_month = '{}-{}'.format(self.year, self.month)
        self.api_dict = api_dict

    @logger
    def is_job_finished(self, status_url):
        request_response = self.request_job_data(job_url=status_url)
        if request_response is None or not request_response:
            raise RuntimeError('m=is_job_finished, status_url={}, msg=response is invalid'.format(status_url))

        response = json.loads(request_response)
        if response['status'] is None:
            raise RuntimeError(
                'm=is_job_finished, status_url={}, response_status={}'.format(status_url, response['status']))

        return 'process-running.status/success' in response['status']

    @logger
    def request_job_data(self, job_url):
        job_result = requests.get(
            url=job_url,
            headers={'jwt-token': self.api_dict['token']}
        )

        return job_result.content.decode('utf-8')

    @logger
    def _request_data(self, endpoint_complement):
        url = '{}/{}'.format(self.api_dict['endpoint'], endpoint_complement)
        logger.info('m=_request_data, url={}'.format(url))

        return requests.get(
            url=url,
            headers={'jwt-token': self.api_dict['token']}
        )

    @logger
    def wait_for_results(self, status_url):
        max_wait_count = 360
        wait_count = 0
        while not self.is_job_finished(status_url=status_url) and wait_count < max_wait_count:
            time.sleep(self.api_dict['job-waiting-time'])
            wait_count += 1

        if wait_count == max_wait_count:
            raise RuntimeError('m=wait_for_results, msg=wait for job timed out')

    @logger(exclude='_object')
    def save_into_s3_raw(self, object_, file_path_prefix, raw_table_name):
        BaseETL.obj_to_s3(
            obj_io=object_,
            bucket=self.s3_bucket,
            file_path='{}/ym={}/data.gz'.format(file_path_prefix, self.year_month)
        )

        self.athena_client.upsert_single_partition(
            bucket_folder_path='{}/raw/seu_barriga/invoice/{}'.format(self.s3_bucket, self.type_),
            database='datalake_raw',
            table=raw_table_name,
            partition_name='ym',
            partition_value=self.year_month
        )

    @logger
    def _transform_data(self, query, raw_columns, clean_columns, clean_table_name):
        key = 'clean/seu_barriga/invoice/{}/ym={}/data.parq'.format(self.type_, self.year_month)

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.format(year_month=self.year_month),
            raw_columns=raw_columns,
            clean_columns=clean_columns
        )

        self.athena_client.upsert_single_partition(
            bucket_folder_path='{}/clean/seu_barriga/invoice/{}'.format(self.s3_bucket, self.type_),
            database='datalake_clean',
            table=clean_table_name,
            partition_name='ym',
            partition_value=self.year_month
        )
