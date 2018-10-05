import json
from abc import abstractmethod
from datetime import datetime
from gzip import GzipFile
from io import BytesIO

import boto3
import pandas as pd
from botocore.exceptions import ClientError
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient
from unidecode import unidecode

from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR, SOURCE_QUERIES_DIR

logger = QuintoAndarLogger('Asterisk')


# TODO: move to generic wrapper
class UnidecodeHandler(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, unicode):
            return unidecode(obj)
        if isinstance(obj, datetime):
            return obj.strftime('%Y-%m-%d %H:%M:%S')

        return unidecode(unicode(str(obj)))


class Asterisk(object):
    DATABASES = {
        'default': 'asterisk',
        'cdr': 'asteriskcdrdb'
    }

    @logger
    def __init__(self, s3_bucket, execution_date):
        self.s3_bucket = s3_bucket
        self.partition_date = execution_date.strftime('%Y-%m-%d')

        self.athena_client = AthenaClient(self.s3_bucket)
        self.s3_resource = boto3.resource('s3')

    # abstract methods
    @abstractmethod
    def extract_and_load_data(self):
        raise NotImplementedError('m=extract_and_load_data, msg=method not implemented')

    @abstractmethod
    def data_existence_check(self, bucket_type):
        raise NotImplementedError('m=data_existence_check, msg=method not implemented')

    @abstractmethod
    def move_to_clean(self):
        raise NotImplementedError('m=move_to_clean, msg=method not implemented')

    # instance methods
    @logger
    def _data_existence_check_partitioned(self, bucket_type, _class):
        file_path = '{}/asterisk/{}/dt={}/data.gz'.format(bucket_type, _class.value, self.partition_date)
        return self.__data_existence_check(bucket_type=bucket_type, _class=_class, file_path=file_path)

    @logger
    def _data_existence_check_full(self, bucket_type, _class):
        file_path = '{}/asterisk/{}/data.gz'.format(bucket_type, _class.value)
        return self.__data_existence_check(bucket_type=bucket_type, _class=_class, file_path=file_path)

    @logger
    def __data_existence_check(self, bucket_type, _class, file_path):
        if bucket_type not in ('raw', 'clean'):
            logger.error('m=__data_existence_check, bucket_type={}, msg=invalid bucket type'.format(bucket_type))
            raise ValueError

        try:
            self.s3_resource.Object(self.s3_bucket, file_path).load()
        except ClientError as e:
            if e.response['Error']['Code'] == '404':
                return False  # file does not exist
            raise  # something else had gone wrong

        return True

    @logger
    def _extract_and_load_data_partitioned(self, _class):
        query = BaseETL.get_query_from_file_name(
            '{}/asterisk/extract_{}_data.sql'.format(SOURCE_QUERIES_DIR, _class.value))

        file_suffix = 'raw/asterisk/{}/dt={}/data.gz'.format(_class.value, self.partition_date)
        self.__extract_and_load_data(
            query=query.format(partition_date=self.partition_date),
            _class=_class,
            file_suffix=file_suffix
        )

    @logger
    def _extract_and_load_data_full(self, _class):
        query = BaseETL.get_query_from_file_name(
            '{}/asterisk/extract_{}_data.sql'.format(SOURCE_QUERIES_DIR, _class.value))

        file_suffix = 'raw/asterisk/{}/data.gz'.format(_class.value)
        self.__extract_and_load_data(
            query=query,
            _class=_class,
            file_suffix=file_suffix
        )

    @logger
    def __extract_and_load_data(self, query, _class, file_suffix):
        table_data = BaseETL.from_db_query(
            query=query,
            db_enum=EnumDB.QuintoAndar_asterisk
        )

        json_list = self.__convert_table_data_to_json_list(table_data=table_data)
        self.__save_to_s3(
            json_list=json_list,
            _class=_class,
            file_suffix=file_suffix
        )

    @logger(exclude='table_data')
    def __convert_table_data_to_json_list(self, table_data):
        df = pd.DataFrame(table_data[1:], columns=table_data[0])
        df_json = df.to_json(orient='records', date_format='iso', force_ascii=False)
        return json.loads(df_json, encoding='latin-1')

    @logger(exclude='json_list')
    def __save_to_s3(self, json_list, _class, file_suffix):
        if json_list is None or len(json_list) == 0:
            logger.info('m=__save_to_s3, msg=no results')
            return

        logger.info('m=__save_to_s3, msg=gzipping json_list')
        gz_body = BytesIO()
        for _json in json_list:
            with GzipFile(fileobj=gz_body, mode='w') as fp:
                fp.write((json.dumps(_json, ensure_ascii=False, cls=UnidecodeHandler)).encode('utf-8'))
                fp.write('\n')

        self.__obj_to_s3(
            obj_io=gz_body,
            file_suffix=file_suffix
        )

        # clear obj allocation
        # only flushing does not clear the buffer
        gz_body.seek(0)
        gz_body.flush()

        logger.info('m=__save_to_s3, msg={} rows saved'.format(len(json_list)))

    def __obj_to_s3(self, obj_io, file_suffix):
        logger.info('m=__obj_to_s3, file_suffix={}, msg=sending to s3'.format(file_suffix))
        BaseETL.obj_to_s3(
            obj_io=obj_io,
            bucket=self.s3_bucket,
            file_path=file_suffix
        )
        logger.info('m=__obj_to_s3, file_suffix={}, msg=sent to s3'.format(file_suffix))

    @logger
    def _upsert_partition(self, bucket_type, _class):
        if bucket_type not in ('raw', 'clean'):
            raise ValueError('m=_upsert_partition, bucket_type={}, msg=invalid bucket type'.format(bucket_type))

        self.athena_client.upsert_single_partition(
            bucket_folder_path='{}/{}/asterisk/{}'.format(self.s3_bucket, bucket_type, _class.value),
            database='datalake_{}'.format(bucket_type),
            table='asterisk_{}'.format(_class.value),
            partition_name='dt',
            partition_value=self.partition_date
        )

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean_partitioned(self, _class, r_cols, c_cols):
        key = 'clean/asterisk/{}/dt={}/data.parq'.format(_class.value, self.partition_date)
        self.__move_to_clean(
            _class=_class,
            key=key,
            r_cols=r_cols,
            c_cols=c_cols,
            partition_date=self.partition_date
        )

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean_full(self, _class, r_cols, c_cols):
        key = 'clean/asterisk/{}/data.parq'.format(_class.value)
        self.__move_to_clean(
            _class=_class,
            key=key,
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger(exclude=['r_cols', 'c_cols'])
    def __move_to_clean(self, _class, key, r_cols, c_cols, **params):
        query = BaseETL.get_query_from_file_name(
            '{}/asterisk/create_{}_table.sql'.format(DATALAKE_QUERIES_DIR, _class.value)
        )

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.format(**params),
            raw_columns=r_cols,
            clean_columns=c_cols
        )
