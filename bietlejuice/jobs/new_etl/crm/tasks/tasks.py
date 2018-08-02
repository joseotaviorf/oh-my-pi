import json
from abc import abstractmethod
from datetime import datetime
from gzip import GzipFile
from io import BytesIO

import boto3
from pymongo import MongoClient
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger
from unidecode import unidecode

from bietlejuice.jobs.base.enum_db import EnumDb
from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR, DW_QUERIES_DIR


# TODO: move to generic wrapper
class UnidecodeHandler(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, unicode):
            return unidecode(obj)
        if isinstance(obj, datetime):
            return obj.strftime('%Y-%m-%d %H:%M:%S')

        return unidecode(unicode(str(obj)))


class CRMTasks(object):
    DEFAULT_FIELDS_PROJECTION = {
        'metadata.inquilino.dataExpedicaoRg': False,
        'metadata.proprietario.dataExpedicaoRg': False
    }

    BUCKET_FOLDER_SUFFIX = 'crm/tasks'

    SCHEMA_NAME = 'crm'

    @logger(exclude='mongo_client_uri')
    def __init__(self, s3_bucket, mongo_client_uri, _class, execution_date):
        self.s3_bucket = s3_bucket
        self.mongo_client = MongoClient(mongo_client_uri)
        self._class = _class
        self.execution_date_from = execution_date.replace(hour=0, minute=0, second=0, microsecond=0)
        self.partition_date = self.execution_date_from.strftime('%Y-%m-%d')
        self.execution_date_to = execution_date.replace(hour=23, minute=59, second=59, microsecond=59)

        self.athena_client = AthenaClient(self.s3_bucket)
        self.s3_resource = boto3.resource('s3')

    # abstract methods
    @abstractmethod
    def extract_and_load_data(self):
        _logger.error('m=extract_and_load_data, msg=method not implemented')
        raise NotImplementedError

    @abstractmethod
    def move_to_clean(self):
        _logger.error('m=move_to_clean, msg=method not implemented')
        raise NotImplementedError

    # instance methods
    def __add_incremental_constraints(self, _type):
        _logger.info('m=__add_incremental_constraints, msg=init')

        if _type is None:
            _logger.info('m=__add_incremental_constraints, _type=None')
            raise ValueError

        if isinstance(_type, list):
            # TODO add '$in' field to contemplate multiple CRM queues
            _filter = None

        else:
            _filter = {
                '$and': [{
                    'type': _type,  # adding child previous filter
                    'actions.date': {
                        '$gte': self.execution_date_from,
                        '$lte': self.execution_date_to
                    }
                }]
            }

        return _filter

    @logger
    def _extract_and_load_data(self, _type, fields_projection=None):
        incremental_filter = self.__add_incremental_constraints(_type)

        db = self.mongo_client.tasks
        collection_gen = db.tasks.find(
            filter=incremental_filter,
            projection=fields_projection if fields_projection is not None else CRMTasks.DEFAULT_FIELDS_PROJECTION
        ).batch_size(10000)  # reduces the number of trips to the server

        total_count = collection_gen.count()
        _logger.info('m=extract_and_load_data, msg=processing {} rows'.format(total_count))
        self.__save_to_s3(
            json_list=collection_gen,
            total_count=total_count
        )

    @logger
    def __delete_old_files(self):
        key = 'raw/{}/{}/dt={}/'.format(CRMTasks.BUCKET_FOLDER_SUFFIX,
                                        self._class,
                                        self.partition_date)
        s3_bucket_obj = self.s3_resource.Bucket(self.s3_bucket)

        _files = (s3_bucket_obj
                  .objects
                  .filter(Prefix=key)
                  )

        list_files = list(_files)
        if _files is None or len(list_files) == 0:
            return

        response = (s3_bucket_obj
                    .objects
                    .filter(Prefix=list_files[0].key)  # deleting entire folder
                    .delete())

        if (response is None or
                len(response) == 0 or
                'ResponseMetadata' not in response[0] or
                'HTTPStatusCode' not in response[0]['ResponseMetadata'] or
                response[0]['ResponseMetadata']['HTTPStatusCode'] != 200):
            _logger.error('m=__delete_old_files, key={}, msg=error deleting files from S3'.format(key))
            raise Exception

    @logger(exclude='json_list')
    def __save_to_s3(self, json_list, total_count):
        self.__delete_old_files()

        _logger.info('m=__save_to_s3, msg=gzipping json_list')

        gz_body = BytesIO()
        for _json in json_list:
            with GzipFile(fileobj=gz_body, mode='w') as fp:
                fp.write((json.dumps(_json, ensure_ascii=False, cls=UnidecodeHandler)).encode('utf-8'))
                fp.write('\n')

        # don't need to clear old entries since the data volume always grows big
        file_suffix = 'raw/{}/{}/dt={}/data.gz'.format(CRMTasks.BUCKET_FOLDER_SUFFIX,
                                                       self._class,
                                                       self.partition_date)
        self.__obj_to_s3(
            obj_io=gz_body,
            file_suffix=file_suffix
        )

        # clear obj allocation
        # only flushing does not clear the buffer
        gz_body.seek(0)
        gz_body.flush()

        _logger.info('m=__save_to_s3, msg={} rows saved'.format(total_count))

    def __obj_to_s3(self, obj_io, file_suffix):
        _logger.info('m=__obj_to_s3, file_suffix={}, msg=sending to s3'.format(file_suffix))
        BaseETL.obj_to_s3(
            obj_io=obj_io,
            bucket=self.s3_bucket,
            file_path=file_suffix
        )
        _logger.info('m=__obj_to_s3, file_suffix={}, msg=sent to s3'.format(file_suffix))

    @logger
    def _upsert_partition(self, bucket_type):
        self.athena_client.upsert_single_partition(
            bucket_folder_path='{}/{}/{}/{}'.format(self.s3_bucket,
                                                    bucket_type,
                                                    CRMTasks.BUCKET_FOLDER_SUFFIX,
                                                    self._class),
            database='datalake_{}'.format(bucket_type),
            table='crm_tasks_{}'.format(self._class),
            partition_name='dt',
            partition_value=self.partition_date
        )

    @logger
    def _move_to_clean(self, query, raw_columns, clean_columns):
        key = 'clean/{}/{}/dt={}/data.parq'.format(CRMTasks.BUCKET_FOLDER_SUFFIX, self._class, self.partition_date)
        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.format(partition_date=self.partition_date),
            raw_columns=raw_columns,
            clean_columns=clean_columns
        )

    @logger
    def _load_dim(self):
        filename = '{}/{}/{}/create_dim.sql'.format(DATALAKE_QUERIES_DIR, CRMTasks.BUCKET_FOLDER_SUFFIX, self._class)
        self._move_to_dw(
            filename=filename,
            table_name='dim_{}_task'.format(self._class)
        )

    @logger
    def _load_fact(self):
        filename = '{}/{}/{}/create_fact.sql'.format(DATALAKE_QUERIES_DIR, CRMTasks.BUCKET_FOLDER_SUFFIX, self._class)
        self._move_to_dw(
            filename=filename,
            table_name='fact_{}_tasks'.format(self._class)
        )

    @logger
    def _move_to_dw(self, filename, table_name):
        query = BaseETL.get_query_from_file_name(filename)
        df = self.athena_client.execute_query_and_return_dataframe(
            query.replace('__PARTITION_DATE__', self.partition_date))

        self.__delete_old_entries(
            sk_list=set(df['sk_credit_task']),
            table_name=table_name
        )

        BaseETL.dataframe_to_db(
            df=df,
            table_name='{}.{}'.format(CRMTasks.SCHEMA_NAME, table_name),
            enum_db=EnumDb.BI_DW,
            encoding='utf-8',
            append=False
        )

    def __delete_old_entries(self, sk_list, table_name):
        _logger.info('m=__delete_old_entries, table_name={}, sk_list length={}'.format(table_name, len(sk_list)))

        sks = ', '.join("'{}'".format(sk) for sk in sk_list)
        query = BaseETL.get_query_from_file_name(file_name='{}/crm/delete_old_entries.sql'.format(DW_QUERIES_DIR))

        BaseETL.execute_command(
            command=query.format(schema=CRMTasks.SCHEMA_NAME, table_name=table_name, sk_column='sk_credit_task',
                                 sks=sks),
            db_enum=EnumDb.BI_DW,
            encoding='utf-8',
            commit=True
        )
