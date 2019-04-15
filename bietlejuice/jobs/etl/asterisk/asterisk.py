from abc import abstractmethod
from gzip import GzipFile
from io import BytesIO

import boto3
import pandas as pd
from botocore.exceptions import ClientError
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR, SOURCE_QUERIES_DIR

logger = QuintoAndarLogger('Asterisk')


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
    def _data_existence_check_partitioned(self, bucket_type, class_):
        file_path = '{}/asterisk/{}/dt={}/data.gz'.format(bucket_type, class_.value, self.partition_date)
        return self.__data_existence_check(bucket_type, file_path)

    @logger
    def _data_existence_check_full(self, bucket_type, class_):
        file_path = '{}/asterisk/{}/data.gz'.format(bucket_type, class_.value)
        return self.__data_existence_check(bucket_type, file_path)

    @logger
    def __data_existence_check(self, bucket_type, file_path):
        if bucket_type not in ('raw', 'clean'):
            raise ValueError(('m=__data_existence_check, bucket_type={}, msg=invalid bucket type'.format(bucket_type)))
        try:
            self.s3_resource.Object(self.s3_bucket, file_path).load()
        except ClientError as e:
            if e.response['Error']['Code'] == '404':
                return False  # file does not exist
            raise  # something else had gone wrong

        return True

    @logger
    def _extract_and_load_data_partitioned(self, class_):
        query = BaseETL.get_query_from_file_name(
            '{}/asterisk/extract_{}_data.sql'.format(SOURCE_QUERIES_DIR, class_.value))

        file_suffix = 'raw/asterisk/{}/dt={}/data.gz'.format(class_.value, self.partition_date)
        self.__extract_and_load_data(
            query=query.format(partition_date=self.partition_date),
            file_suffix=file_suffix
        )

    @logger
    def _extract_and_load_data_full(self, class_):
        query = BaseETL.get_query_from_file_name(
            '{}/asterisk/extract_{}_data.sql'.format(SOURCE_QUERIES_DIR, class_.value))

        file_suffix = 'raw/asterisk/{}/data.gz'.format(class_.value)
        self.__extract_and_load_data(
            query=query,
            file_suffix=file_suffix
        )

    @logger
    def __extract_and_load_data(self, query, file_suffix):
        table_data = BaseETL.from_db_query(
            query=query,
            db_enum=EnumDB.QuintoAndar_asterisk
        )

        df = pd.DataFrame(table_data[1:], columns=table_data[0])

        gz_body = BytesIO()
        with GzipFile(fileobj=gz_body, mode='w') as fp:
            for _, row in df.iterrows():
                row.to_json(fp, date_format='iso', date_unit='ms', force_ascii=False)
                fp.write('\n')

        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=self.s3_bucket,
            file_path=file_suffix
        )

        # clear obj allocation
        # only flushing does not clear the buffer
        gz_body.seek(0)
        gz_body.flush()

    @logger
    def _upsert_single_partition(self, bucket_type, class_):
        if bucket_type not in ('raw', 'clean'):
            raise ValueError('m=_upsert_partition, bucket_type={}, msg=invalid bucket type'.format(bucket_type))

        self.athena_client.upsert_single_partition(
            bucket_folder_path='{}/{}/asterisk/{}'.format(self.s3_bucket, bucket_type, class_.value),
            database='datalake_{}'.format(bucket_type),
            table='asterisk_{}'.format(class_.value),
            partition_name='dt',
            partition_value=self.partition_date
        )

    @logger
    def _upsert_partition(self, bucket_type, class_, partition_name_list, partition_value_list):
        if bucket_type not in ('raw', 'clean'):
            raise ValueError('m=_upsert_partition, bucket_type={}, msg=invalid bucket type'.format(bucket_type))

        self.athena_client.upsert_partition(
            bucket_folder_path='{}/{}/asterisk/{}'.format(self.s3_bucket, bucket_type, class_.value),
            database='datalake_{}'.format(bucket_type),
            table='asterisk_{}'.format(class_.value),
            partition_name_list=partition_name_list,
            partition_value_list=partition_value_list
        )

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean_partitioned(self, class_, r_cols, c_cols):
        key = 'clean/asterisk/{}/dt={}/data.parq'.format(class_.value, self.partition_date)
        self._move_to_clean(
            class_=class_,
            key=key,
            r_cols=r_cols,
            c_cols=c_cols,
            partition_date=self.partition_date
        )

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean_full(self, class_, r_cols, c_cols):
        key = 'clean/asterisk/{}/data.parq'.format(class_.value)
        self._move_to_clean(
            class_=class_,
            key=key,
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean(self, class_, key, r_cols, c_cols, **params):
        query = BaseETL.get_query_from_file_name(
            '{}/asterisk/create_{}_table.sql'.format(DATALAKE_QUERIES_DIR, class_.value)
        )

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.format(**params),
            raw_columns=r_cols,
            clean_columns=c_cols
        )
