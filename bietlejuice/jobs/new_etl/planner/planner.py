import json
from abc import abstractmethod
from datetime import timedelta
from gzip import GzipFile
from io import BytesIO

import boto3
import requests
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR

logger = QuintoAndarLogger('Planner')


class Planner(object):
    @logger
    def __init__(self, s3_bucket, execution_date):
        self.s3_bucket = s3_bucket
        self.execution_date = (execution_date + timedelta(days=1)).strftime('%Y-%m-%d')

        self.athena_client = AthenaClient(self.s3_bucket)
        self.s3_resource = boto3.resource('s3')

    # abstract methods
    @abstractmethod
    def get_class_ids(self):
        raise NotImplementedError('m=get_class_ids, msg=method not implemented')

    @abstractmethod
    def extract_data(self, id_class):
        raise NotImplementedError('m=extract_data, msg=method not implemented')

    @abstractmethod
    def save_into_s3_raw(self, _json, id_class):
        raise NotImplementedError('m=save_into_s3_raw, msg=method not implemented')

    @abstractmethod
    def upsert_single_raw_partition(self, id_class):
        raise NotImplementedError('m=upsert_single_raw_partition, msg=method not implemented')

    @abstractmethod
    def upsert_single_clean_partition(self, id_class):
        raise NotImplementedError('m=upsert_single_clean_partition, msg=method not implemented')

    @abstractmethod
    def move_to_clean(self, id_class):
        raise NotImplementedError('m=move_to_clean, msg=method not implemented')

    # instance methods
    @logger
    def _get_class_ids(self, enum_type):
        ids_df = self.athena_client.execute_file_query_and_return_dataframe(
            filename='{}/planner/{}_ids.sql'.format(DATALAKE_QUERIES_DIR, enum_type.value))
        if ids_df is None:
            raise RuntimeError('m=_get_class_ids_as_json, msg=ids_df is None')

        return ids_df['id'].tolist()

    @logger
    def _extract_data(self, endpoint, **params):
        response = requests.get(url=endpoint.format(**params))
        if response.status_code != 200:
            raise RuntimeError(
                'm=_extract_data, response_status_code={}, response_content={}'.format(response.status_code,
                                                                                       response.content))

        json_response = response.json()
        if json_response is None:
            raise RuntimeError('m=_extract_data, msg=json_response is None')

        return json_response

    @logger
    def _save_into_s3_raw(self, _json, enum_type, id_class):
        if _json is None:
            raise AttributeError('m=_save_into_s3_raw, msg=_json is none')

        gz_body = BytesIO()
        with GzipFile(fileobj=gz_body, mode='w') as fp:
            fp.write((json.dumps(_json, ensure_ascii=False)).encode('utf-8'))

        file_suffix = 'raw/planner/dt={}/{}={}/data.gz'.format(self.execution_date, enum_type.value, id_class)
        logger.info('m=_save_into_s3_raw, file_suffix={}, msg=sending to s3'.format(file_suffix))
        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=self.s3_bucket,
            file_path=file_suffix
        )
        logger.info('m=_save_into_s3_raw, file_suffix={}, msg=sent to s3'.format(file_suffix))

        # clear obj allocation
        # only flushing does not clear the buffer
        gz_body.seek(0)
        gz_body.flush()

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean(self, enum_type, id_class, r_cols, c_cols):
        key = 'clean/planner/dt={}/{}={}/data.parq'.format(self.execution_date, enum_type.value, id_class)
        query = BaseETL.get_query_from_file_name(
            '{}/planner/{}_raw_transform.sql'.format(DATALAKE_QUERIES_DIR, enum_type.value)
        )

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.format(date=self.execution_date, id_class=id_class),
            raw_columns=r_cols,
            clean_columns=c_cols
        )

    @logger
    def _upsert_single_raw_partition(self, enum_type, id_class):
        self.__upsert_single_partition(
            enum_type=enum_type,
            id_class=id_class,
            bucket_type='raw'
        )

    @logger
    def _upsert_single_clean_partition(self, enum_type, id_class):
        self.__upsert_single_partition(
            enum_type=enum_type,
            id_class=id_class,
            bucket_type='clean'
        )

    @logger
    def __upsert_single_partition(self, enum_type, id_class, bucket_type):
        if bucket_type not in ('raw', 'clean'):
            raise ValueError('m=__upsert_single_partition, bucket_type={}, msg=invalid bucket type'.format(bucket_type))

        self.athena_client.execute_file_query_and_wait_for_results(
            filename='{}/planner/upsert_single_partition.sql'.format(DATALAKE_QUERIES_DIR),
            query_params={
                'schema': 'datalake_{}'.format(bucket_type),
                'enum_value': enum_type.value,
                'dt_partition': self.execution_date,
                'id_class': id_class,
                's3_bucket': self.s3_bucket,
                'bucket_type': bucket_type
            }
        )
