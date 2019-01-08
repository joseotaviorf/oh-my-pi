import json
import time
from abc import abstractmethod
from gzip import GzipFile
from io import BytesIO

import requests
from enum import Enum
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR

logger = QuintoAndarLogger('Workable')


class Workable(object):
    class TypeEnum(Enum):
        MEMBERS = 'members'
        RECRUITERS = 'recruiters'
        STAGES = 'stages'
        JOBS = 'jobs'
        CANDIDATES = 'candidates'
        EVENTS = 'events'

    DEFAULT_REQUEST_LIMIT = 50
    LIMIT_SUFFIX = 'limit={}'.format(DEFAULT_REQUEST_LIMIT)

    PAGING_LIMIT = 10 ** 6

    TABLE_NAMES = {
        'fact': 'fact_recruitment'
    }

    DEFAULT_WAITING_REQUEST_HIT = 2

    @logger(exclude='access_token')
    def __init__(self, s3_bucket, url_prefix, access_token):
        self.url_prefix = url_prefix
        self.request_headers = {
            'Content-Type': 'application/json',
            'authorization': 'Bearer {}'.format(access_token)
        }

        self.s3_bucket = s3_bucket
        self.athena_client = AthenaClient(s3_bucket)

    # abstract methods
    @abstractmethod
    def extract_data(self):
        raise NotImplementedError('m=extract_data, msg=method not implemented')

    @abstractmethod
    def save_into_s3_raw(self, json_list):
        raise NotImplementedError('m=save_into_s3_raw, msg=method not implemented')

    @abstractmethod
    def move_to_clean(self):
        raise NotImplementedError('m=move_to_clean, msg=method not implemented')

    @abstractmethod
    def move_to_staging_dim(self):
        raise NotImplementedError('m=move_to_staging_dim, msg=method not implemented')

    @abstractmethod
    def move_dim_to_dw(self):
        raise NotImplementedError('m=move_dim_to_dw, msg=method not implemented')

    @abstractmethod
    def delete_dim_staging_entries(self):
        raise NotImplementedError('m=delete_dim_staging_entries, msg=method not implemented')

    # instance methods
    @logger
    def _extract_data(self, enum_type):
        enum_value = enum_type.value
        list_data = []
        url = '{}/{}?{}'.format(self.url_prefix, enum_value, Workable.LIMIT_SUFFIX)

        paging_index = 0
        while paging_index < Workable.PAGING_LIMIT:
            response = requests.get(
                url=url,
                headers=self.request_headers
            )

            if response.status_code not in (200, 429):
                raise RuntimeError(
                    'm=_extract_data, response_status_code={}, response_content={}'.format(response.status_code,
                                                                                           response.content))

            sleep_count = 0
            while response.status_code == 429:
                if sleep_count > 5:
                    raise RuntimeError('m=_extract_data, msg=exceeded sleep limit')

                if 'X-Rate-Limit-Reset' not in response.headers:
                    raise RuntimeError('m=_extract_data, msg=X-Rate-Limit-Reset not present in headers')

                sleep_seconds = int(response.headers['X-Rate-Limit-Reset']) - int(time.time())
                if sleep_seconds <= 0:
                    sleep_seconds = Workable.DEFAULT_WAITING_REQUEST_HIT

                logger.warn(
                    'm=_extract_data, msg=exceeded rate limit, sleeping for {} seconds...'.format(sleep_seconds))

                time.sleep(sleep_seconds)

                response = requests.get(
                    url=url,
                    headers=self.request_headers
                )

                sleep_count += 1

            response_json = response.json()
            if 'paging' not in response_json or \
                    'next' not in response_json['paging'] or \
                    len(response_json[enum_value]) == 0:
                return list_data

            list_data += response_json[enum_value]
            url = response_json['paging']['next']
            paging_index += 1
            time.sleep(Workable.DEFAULT_WAITING_REQUEST_HIT)

            logger.info('m=_extract_data, enum_value={}, page_number={}'.format(enum_value, paging_index))

        raise RuntimeError('m=_extract_data, enum_value={}, msg=exceeded paging limit'.format(enum_value))

    @logger(exclude='json_list')
    def _save_into_s3_raw(self, json_list, enum_type):
        if json_list is None:
            raise AttributeError('m=save_into_s3, msg=json_list is none')

        gz_body = BytesIO()
        count = 0
        for _json in json_list:
            with GzipFile(fileobj=gz_body, mode='w') as fp:
                fp.write((json.dumps(_json, ensure_ascii=False)).encode('utf-8'))
                fp.write('\n')

            count += 1

        file_suffix = 'raw/workable/{}/data.gz'.format(enum_type.value)
        logger.info('m=__obj_to_s3, file_suffix={}, msg=sending to s3'.format(file_suffix))
        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=self.s3_bucket,
            file_path=file_suffix
        )
        logger.info('m=__obj_to_s3, file_suffix={}, msg=sent to s3'.format(file_suffix))

        # clear obj allocation
        # only flushing does not clear the buffer
        gz_body.seek(0)
        gz_body.flush()

        logger.info('m=__save_to_s3, msg={} rows saved'.format(count))

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean(self, enum_type, r_cols, c_cols):
        key = 'clean/workable/{}/data.parq'.format(enum_type.value)

        query = BaseETL.get_query_from_file_name(
            '{}/workable/{}/raw_transform.sql'.format(DATALAKE_QUERIES_DIR, enum_type.value)
        )

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query,
            raw_columns=r_cols,
            clean_columns=c_cols
        )

    @logger
    def _move_to_staging_dim(self, enum_type, table_name):
        self.__move_to_staging(
            table_name='dim_{}'.format(table_name),
            file_name='{}/staging_dim_table.sql'.format(enum_type.value)
        )

    @logger
    def _move_to_staging_fact(self):
        self.__move_to_staging(
            table_name='fact_recruitment',
            file_name='staging_fact_table.sql'
        )

    @logger
    def __move_to_staging(self, table_name, file_name):
        query = BaseETL.get_query_from_file_name('{}/workable/{}'.format(DATALAKE_QUERIES_DIR, file_name))
        df = self.athena_client.execute_query_and_return_dataframe(query)

        BaseETL.dataframe_to_db(
            df=df,
            table_name='staging.workable_{}'.format(table_name),
            enum_db=EnumDB.BI_DW,
            encoding='utf-8',
            append=False
        )

    @logger
    def _move_to_dw(self, table_name):
        table_data = BaseETL.from_db_table(
            db_enum=EnumDB.BI_DW,
            table_name='staging.workable_{}'.format(table_name),
            encoding='utf-8'
        )

        BaseETL.bulk_insert(
            table=table_data,
            table_name='workable.{}'.format(table_name),
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
            append=False
        )

    @logger
    def _delete_staging_entries(self, table_name):
        BaseETL.execute_command(
            command='delete from staging.workable_{}'.format(table_name),
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
            commit=True
        )
