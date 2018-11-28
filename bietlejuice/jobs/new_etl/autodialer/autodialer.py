import json
import re
from io import BytesIO
from os import listdir

import boto3
import numpy as np
import pandas as pd
from __init__ import AUTODIALER_DATALAKE_QUERIES_DIR
from bietlejuice.jobs.dags.util import environment as env
from bson import json_util
from pandas.io.json import json_normalize
from pymongo import MongoClient, ASCENDING
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

mongo_client_uri = env.get_airflow_env_var('MONGODB_AUTODIALER_URI')
logger = QuintoAndarLogger('Autodialer_ETL')

# TODO
# Create Dynamic data process
dummy_dt = '2010-01-01'


class AutodialerETL(object):
    DOCUMENT_JSON_MAP = {
        'task_references': ['contactInfo', 'dialStatus'],
        'task_reference_inbound_event_histories': ['inboundEvents'],
        'task_reference_outbound_event_histories': ['taskReferenceOutboundEvents']
    }

    def __init__(self, bucket_name, execution_date=None):
        self.s3_bucket = bucket_name
        self.execution_date = execution_date
        self.athena_client = AthenaClient(self.s3_bucket)

        try:
            self.client = MongoClient(mongo_client_uri)
            self.db = self.client.autodialer
        except Exception as ex:
            raise Exception('m=__init__,error={}, msg=Could not connect to mongo'.format(ex))

    # task references
    @logger
    def get_mongo_data(self, document_type):
        mongo_db = self.__mongo_connect(document_type=document_type)
        raw_data = self.__get_mongo_data(mongo_db)
        return raw_data

    @logger(exclude='df')
    def dump_data_into_datalake(self, df, datalake_folder, document_type):
        dt = 'dt={}'.format(dummy_dt if self.execution_date is None else self.execution_date.strftime('%Y-%m-%d'))
        self.__df_to_s3(df, path='{0}/autodialer/{1}/{2}/tr.csv'.format(datalake_folder, document_type, dt))
        logger.info("m=dump_data_into_datalake, "
                    " datalake_folder={0},"
                    " document_type={1},"
                    " execution_date={2},"
                    " df_length={3}, "
                    " msg=Df dumped into datalake!".format(datalake_folder,
                                                           document_type,
                                                           str(self.execution_date) if self.execution_date else 'None',
                                                           str(len(df))))

    # aux methods
    @logger(exclude='df')
    def __df_to_s3(self, df, path):
        csv_buffer = BytesIO()
        df.to_csv(csv_buffer, index=False, encoding='utf8', sep=';')
        s3 = boto3.resource('s3')
        s3.Bucket(self.s3_bucket).put_object(
            Body=csv_buffer.getvalue(),
            Key=path
        )

    @logger
    def __mongo_connect(self, document_type):
        if document_type == 'task_references':
            return self.db.taskReferences
        if document_type == 'task_reference_inbound_event_histories':
            return self.db.taskReferenceInboundEventHistories
        if document_type == 'task_reference_outbound_event_histories':
            return self.db.taskReferenceOutboundHistory
        else:
            raise ValueError('m=connect, document_type={}, msg=Invalid document type.'.format(document_type))

    @logger(exclude='mongo_db')
    def __get_mongo_data(self, mongo_db):
        filter = None if self.execution_date is not None else ''

        documents = mongo_db.find().sort("_id", ASCENDING)
        return pd.DataFrame(list(documents))

    @logger
    def get_athena_data(self, document_type, filequery):
        filequery = '{}/{}/{}'.format(AUTODIALER_DATALAKE_QUERIES_DIR, document_type, filequery)
        return self.athena_client.execute_file_query_and_return_dataframe(filename=filequery)

    @logger
    def _move_data_to_raw(self, document_type):
        df = self.get_mongo_data(document_type)

        for field in AutodialerETL.DOCUMENT_JSON_MAP[document_type]:
            df[field] = df[field].apply(json.dumps, default=json_util.default)

        self.dump_data_into_datalake(df, 'raw', document_type)

    @logger(exclude='df')
    def _move_data_to_clean(self, document_type, unnest_df=False, treat_df=False):
        path, dir_files = self.get_files_list(document_type)

        for _file in dir_files:
            table_name = _file.split(".")[0]

            self.athena_client.add_partition(
                database='datalake_raw',
                table_name=document_type,
                partition="dt='{}'".format(
                    dummy_dt if self.execution_date is None else self.execution_date.strftime('%Y-%m-%d')))

            df = self.get_athena_data(document_type=document_type, filequery=_file)
            logger.info('m=move_data_to_clean, file={}, msg=Query executed.'.format(dir_files))

            # steps to treat data
            if unnest_df:
                df = self.__unnest_list_columns(df)
            if treat_df:
                df = self.__normalize_json_columns(df, unnest_df)

            # save file
            dt = 'dt={}'.format(
                dummy_dt if self.execution_date is None else self.execution_date.strftime('%Y-%m-%d'))
            key = 'clean/autodialer/{0}/{1}/{2}/file.parq'.format(document_type, table_name, dt)
            self.athena_client.create_parquet_from_df(key=key, df=df)
            logger.info('m=move_data_to_clean, key={}, msg=File created in s3.'.format(key))

            self.athena_client.add_partition(
                database='datalake_clean',
                table_name='{}_{}'.format('autodialer', table_name),
                partition="dt='{}'".format(
                    dummy_dt if self.execution_date is None else self.execution_date.strftime('%Y-%m-%d')))
            logger.info('m=move_data_to_clean, msg=Created partition in clean.'.format(key))

        if len(dir_files) > 0:
            pass
        else:
            logger.error('m=move_data_to_clean, path={}, msg=No query file found.'.format(path))

    @logger
    def get_files_list(self, document_type):
        path = '{}/{}'.format(AUTODIALER_DATALAKE_QUERIES_DIR, document_type)
        return path, listdir(path)

    @logger(exclude='df')
    def __normalize_json_columns(self, df, unnest_df):
        df.replace('', np.nan, inplace=True)

        df_treatment = df.head(1)
        df_treated = df

        for column in df_treatment:
            try:
                # Remove escaped double double-quotes
                df[column].replace('\"\"[^,;\n]+\"\"', '', inplace=True, regex=True)

                if unnest_df:
                    df_json = df[column]
                else:
                    df_json = df[column].apply(json.loads)

                df_concat = json_normalize(df_json)

                df_treated = pd.concat([df_treated, df_concat], axis=1)
                df_treated.drop(column, axis=1, inplace=True)

                # Remove df from memory to use it again in the next iteration
                del df_concat
                logger.info('m=normalize_json_columns, column={}, msg=Json normalized'.format(str(column)))
            except Exception:
                logger.info('m=normalize_json_columns, column={}, msg=Not Json'.format(str(column)))

        old_columns = df_treated.columns
        snake_case_columns = self.__to_snake_case_columns(old_columns)
        df_treated.rename(columns=snake_case_columns, inplace=True)

        # final treatment
        # remove duplicated columns
        df_unique_columns = df_treated.T.groupby(level=0).first().T
        df_unique_columns.replace('', np.NaN, inplace=True)

        return df_unique_columns

    @logger(exclude='df')
    def __unnest_list_columns(self, df):
        # TODO
        #  get lists

        for column in df:
            try:
                # Remove escaped double double-quotes
                df[column].replace('\"\"(?!,|}|])', '', inplace=True, regex=True)
                logger.info('m=__unnest_list_columns, column={}, msg=Column treated'.format(str(column)))
            except Exception:
                logger.info('m=__unnest_list_columns, column={}, msg=Column not treated'.format(str(column)))

        # Treating empty values as a empty list
        df.replace('', '[]', inplace=True)

        # debbug
        # for item in df['inbound_events']:
        #     try:
        #         t = json.loads(item)
        #         print t
        #     except:
        #         print 'a'

        df_unnested = df['inbound_events'].apply(lambda x: json.loads(x)) \
            .apply(pd.Series) \
            .stack() \
            .reset_index(level=1, drop=True) \
            .to_frame('inbound_events') \
            .join(df.drop(columns='inbound_events'), how='left')

        return df_unnested.reset_index()

    def __to_snake_case_columns(self, old_columns):
        _underscorer1 = re.compile(r'(.)([A-Z][a-z]+)')
        _underscorer2 = re.compile('([a-z0-9])([A-Z])')

        new_columns = {}

        for old_column in old_columns:
            subbed = _underscorer1.sub(r'\1_\2', old_column)
            new_column = _underscorer2.sub(r'\1_\2', subbed).lower()
            # get only before dot
            new_column = new_column.split('.')[0]
            new_columns.update({old_column: new_column})

        return new_columns


class TaskReference(AutodialerETL):
    def __init__(self, bucket_name, execution_date=None):
        super(TaskReference, self).__init__(bucket_name, execution_date)
        self.document_type = 'task_references'

    @logger
    def move_data_to_raw(self):
        self._move_data_to_raw(document_type=self.document_type)

    @logger
    def move_data_to_clean(self):
        self._move_data_to_clean(document_type=self.document_type, treat_df=True)


class TaskReferenceInbound(AutodialerETL):
    def __init__(self, bucket_name, execution_date=None):
        super(TaskReferenceInbound, self).__init__(bucket_name, execution_date)
        self.document_type = 'task_reference_inbound_event_histories'

    @logger
    def move_data_to_raw(self):
        self._move_data_to_raw(document_type=self.document_type)

    @logger
    def move_data_to_clean(self):
        self._move_data_to_clean(document_type=self.document_type, unnest_df=True, treat_df=True)


class TaskReferenceOutbound(AutodialerETL):
    def __init__(self, bucket_name, execution_date=None):
        super(TaskReferenceOutbound, self).__init__(bucket_name, execution_date)
        self.document_type = 'task_reference_outbound_event_histories'

    @logger
    def move_data_to_raw(self):
        self._move_data_to_raw(document_type=self.document_type)

    @logger
    def move_data_to_clean(self):
        self._move_data_to_clean(document_type=self.document_type, unnest_df=True, treat_df=True)


# creating
autodialer = TaskReferenceOutbound('5a-datalake')
# raw
autodialer.move_data_to_raw()
# autodialer.move_data_to_clean()
# clean
# autodialer.move_data_to_clean('task_references')
# task_references or task_reference_inbound_event_histories or task_reference_outbound_history
