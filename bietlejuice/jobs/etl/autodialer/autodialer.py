import json
import re
from datetime import datetime
from gzip import GzipFile
from io import BytesIO
from os import listdir

import numpy as np
import pandas as pd
from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.autodialer.autodialer_enum import AutodialerEnum
from pandas.io.json import json_normalize
from pymongo import MongoClient, ASCENDING
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient
from unidecode import unidecode

logger = QuintoAndarLogger('Autodialer_ETL')

# TODO
# Create Dynamic data process
dummy_dt = '2018-01-01'


class AutodialerETL(object):
    def __init__(self, mongo_client_uri, bucket_name, document_type_enum, execution_date=None):
        self.s3_bucket = bucket_name
        self.execution_date = execution_date
        self.athena_client = AthenaClient(self.s3_bucket)
        self.document_type_enum = document_type_enum
        self.document_type = document_type_enum.value

        try:
            self.client = MongoClient(mongo_client_uri)
            self.db = self.client.autodialer
        except Exception as ex:
            raise Exception('m=__init__,error={}, msg=Could not connect to mongo'.format(ex))

    @logger
    def move_data_to_raw(self):
        df = self.get_mongo_data()

        self.__save_to_s3(
            json_list=df
        )

    @logger(exclude='df')
    def move_data_to_clean(self):
        path, dir_files = self.__get_files_list()

        if len(dir_files) == 0:
            raise Exception('m=move_data_to_clean, path={}, msg=No query file found.'.format(path))

        for _file in dir_files:
            table_name = _file.split(".")[0]

            self.athena_client.add_partition(
                database='datalake_raw',
                table_name=self.document_type,
                partition="dt_extraction='{}'".format(
                    dummy_dt if self.execution_date is None else self.execution_date.strftime('%Y-%m-%d')))

            df = self.__get_athena_data(filequery=_file)
            logger.info('m=move_data_to_clean, file={}, msg=Query executed.'.format(dir_files))

            # treat data
            df = self.__normalize_json_columns(df)

            # save file
            dt = 'dt_extraction={}'.format(
                dummy_dt if self.execution_date is None else self.execution_date.strftime('%Y-%m-%d'))
            key = 'clean/autodialer/{0}/{1}/file.parq'.format(table_name, dt)
            self.athena_client.create_parquet_from_df(key=key, df=df)
            logger.info('m=move_data_to_clean, key={}, msg=File created in s3.'.format(key))

            self.athena_client.add_partition(
                database='datalake_clean',
                table_name='{}_{}'.format('autodialer', table_name),
                partition="dt_extraction='{}'".format(
                    dummy_dt if self.execution_date is None else self.execution_date.strftime('%Y-%m-%d')))
            logger.info('m=move_data_to_clean, msg=Created partition in clean.'.format(key))

    # aux methods
    @logger
    def __mongo_connect(self):
        if self.document_type_enum == AutodialerEnum.TASK_REFERENCES:
            return self.db.taskReferences
        if self.document_type_enum == AutodialerEnum.TASK_REFERENCE_INBOUND_EVENTS:
            return self.db.taskReferenceInboundEventHistories
        if self.document_type_enum == AutodialerEnum.TASK_REFERENCE_OUTBOUND_EVENTS:
            return self.db.taskReferenceOutboundHistory

        raise ValueError(
            'm=__mongo_connect, document_type={}, document_type_enum={}, msg=Invalid document type.'.format(
                self.document_type, self.document_type_enum))

    @logger
    def get_mongo_data(self):
        mongo_db = self.__mongo_connect()
        # TODO
        # Implement dynamic data filter
        filter = None if self.execution_date is not None else ''

        raw_data = mongo_db.find().sort("_id", ASCENDING)
        return raw_data

    @logger
    def __get_athena_data(self, filequery):
        filequery = '{}/autodialer/{}/{}'.format(DATALAKE_QUERIES_DIR, self.document_type, filequery)
        return self.athena_client.execute_file_query_and_return_dataframe(filename=filequery)

    @logger
    def __get_files_list(self):
        path = '{}/autodialer/{}'.format(DATALAKE_QUERIES_DIR, self.document_type)
        return path, listdir(path)

    @logger(exclude='df')
    def __normalize_json_columns(self, df):
        df.replace('', np.nan, inplace=True)

        df_treatment = df.head(1)
        df_treated = df

        for column in df_treatment:
            try:
                df_json = df[column].apply(json.loads)
                df_concat = json_normalize(df_json)

                df_treated = pd.concat([df_treated, df_concat], axis=1)
                df_treated.drop(column, axis=1, inplace=True)

                # Remove df from memory to use it again in the next iteration
                del df_concat
                logger.info('m=__normalize_json_columns, column={}, msg=Json normalized'.format(str(column)))
            except Exception:
                logger.info('m=__normalize_json_columns, column={}, msg=Not Json'.format(str(column)))

        old_columns = df_treated.columns
        snake_case_columns = self.__to_snake_case_columns(old_columns)
        df_treated.rename(columns=snake_case_columns, inplace=True)

        # final treatment
        # remove duplicated columns
        df_unique_columns = df_treated.T.groupby(level=0).first().T
        df_unique_columns.replace('', np.NaN, inplace=True)

        return df_unique_columns

    @logger(exclude='old_columns')
    def __to_snake_case_columns(self, old_columns):
        _underscorer1 = re.compile(r'(.)([A-Z][a-z]+)')
        _underscorer2 = re.compile('([a-z0-9])([A-Z])')

        new_columns = {}

        for old_column in old_columns:
            subbed = _underscorer1.sub(r'\1_\2', old_column)
            new_column = _underscorer2.sub(r'\1_\2', subbed).lower()
            # final treatment for columns name
            new_column = new_column.replace('.', '_')
            new_columns.update({old_column: new_column})

        return new_columns

    @logger(exclude='json_list')
    def __save_to_s3(self, json_list):
        gz_body = BytesIO()
        for _json in json_list:
            with GzipFile(fileobj=gz_body, mode='w') as fp:
                fp.write((json.dumps(_json, ensure_ascii=False, cls=UnidecodeHandler)).encode('utf-8'))
                fp.write('\n')

        file_suffix = 'raw/autodialer/{}/dt_extraction={}/{}.gz'.format(self.document_type,
                                                                        dummy_dt,
                                                                        self.document_type)
        self.__obj_to_s3(
            obj_io=gz_body,
            file_suffix=file_suffix
        )

        # clear obj allocation
        # only flushing does not clear the buffer
        gz_body.seek(0)
        gz_body.flush()

        logger.info('m=__save_to_s3, path={}, msg=file saved'.format(file_suffix))

    def __obj_to_s3(self, obj_io, file_suffix):
        logger.info('m=__obj_to_s3, file_suffix={}, msg=sending to s3'.format(file_suffix))
        BaseETL.obj_to_s3(
            obj_io=obj_io,
            bucket=self.s3_bucket,
            file_path=file_suffix
        )
        logger.info('m=__obj_to_s3, file_suffix={}, msg=sent to s3'.format(file_suffix))


class UnidecodeHandler(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, unicode):
            return unidecode(obj)
        if isinstance(obj, datetime):
            return obj.isoformat(' ') if obj.year >= 1900 else obj.replace(year=obj.year + 2000)

        return unidecode(unicode(str(obj)))
