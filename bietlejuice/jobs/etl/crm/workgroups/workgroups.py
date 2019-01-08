import json
from datetime import datetime
from gzip import GzipFile
from io import BytesIO

import boto3
from ordereddict import OrderedDict
from pymongo import MongoClient
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient
from unidecode import unidecode

from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR

logger = QuintoAndarLogger('CRMWorkgroups')


# TODO: move to generic wrapper
class UnidecodeHandler(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, unicode):
            return unidecode(obj)
        if isinstance(obj, datetime):
            return obj.strftime('%Y-%m-%d %H:%M:%S')

        return unidecode(unicode(str(obj)))


class CRMWorkgroups(object):
    BUCKET_FOLDER_SUFFIX = 'crm/workgroups'

    TABLE_NAME = 'crm_workgroups'

    S3_FILE_NAME = 'data'

    @logger(exclude='mongo_client_uri')
    def __init__(self, s3_bucket, mongo_client_uri):
        self.s3_bucket = s3_bucket
        self.mongo_client = MongoClient(mongo_client_uri)

        self.athena_client = AthenaClient(self.s3_bucket)
        self.s3_resource = boto3.resource('s3')

    # instance methods
    @logger
    def extract_and_load_data(self):
        db = self.mongo_client.tasks
        collection_gen = db.workgroups.find().batch_size(10000)  # reduces the number of trips to the server

        total_count = collection_gen.count()
        logger.info('m=extract_and_load_data, msg=processing {} rows'.format(total_count))
        self.__save_to_s3(
            json_list=collection_gen,
            total_count=total_count
        )

    # TODO: move to an s3 wrapper
    @logger
    def __delete_old_files(self):
        key = 'raw/{}/'.format(CRMWorkgroups.BUCKET_FOLDER_SUFFIX)
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
            logger.error('m=__delete_old_files, key={}, msg=error deleting files from S3'.format(key))
            raise Exception

    # TODO: move to an s3 wrapper
    @logger(exclude='json_list')
    def __save_to_s3(self, json_list, total_count):
        if json_list is None or json_list.count() == 0:
            logger.info('m=__save_to_s3, msg=no results')
            return

        # use the method below if multiple files have to be saved into s3
        # self.__delete_old_files()

        logger.info('m=__save_to_s3, msg=gzipping json_list')

        gz_body = BytesIO()
        for _json in json_list:
            with GzipFile(fileobj=gz_body, mode='w') as fp:
                fp.write((json.dumps(_json, ensure_ascii=False, cls=UnidecodeHandler)).encode('utf-8'))
                fp.write('\n')

        # don't need to clear old entries since the data volume always grows big
        file_suffix = 'raw/{}/{}.gz'.format(CRMWorkgroups.BUCKET_FOLDER_SUFFIX, CRMWorkgroups.S3_FILE_NAME)
        self.__obj_to_s3(
            obj_io=gz_body,
            file_suffix=file_suffix
        )

        # clear obj allocation
        # only flushing does not clear the buffer
        gz_body.seek(0)
        gz_body.flush()

        logger.info('m=__save_to_s3, msg={} rows saved'.format(total_count))

    # TODO: move to s3 wrapper
    def __obj_to_s3(self, obj_io, file_suffix):
        logger.info('m=__obj_to_s3, file_suffix={}, msg=sending to s3'.format(file_suffix))
        BaseETL.obj_to_s3(
            obj_io=obj_io,
            bucket=self.s3_bucket,
            file_path=file_suffix
        )
        logger.info('m=__obj_to_s3, file_suffix={}, msg=sent to s3'.format(file_suffix))

    @logger
    def move_workgroups_to_clean(self):
        r_cols = OrderedDict([
            ('id', str),
            ('task_type', str),
            ('title', str)
        ])

        c_cols = OrderedDict([
            ('id', str),
            ('task_type', str),
            ('title', str)
        ])

        self.__move_to_clean(
            bucket_folder_suffix=CRMWorkgroups.BUCKET_FOLDER_SUFFIX,
            sql_file_name='create_workgroups_table.sql',
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger(exclude=['r_cols', 'c_cols'])
    def __move_to_clean(self, bucket_folder_suffix, sql_file_name, r_cols, c_cols, queries_folder_suffix=None):
        key = 'clean/{}/{}.parq'.format(bucket_folder_suffix, CRMWorkgroups.S3_FILE_NAME)

        query = BaseETL.get_query_from_file_name(
            '{}/{}/{}'.format(DATALAKE_QUERIES_DIR,
                              bucket_folder_suffix if queries_folder_suffix is None else queries_folder_suffix,
                              sql_file_name))

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query,
            raw_columns=r_cols,
            clean_columns=c_cols
        )
