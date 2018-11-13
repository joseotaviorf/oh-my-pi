import json
from os import listdir

import numpy as np
import pandas as pd
from __init__ import AUTODIALER_DATALAKE_QUERIES_DIR
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags.util import environment as env
from pandas.io.json import json_normalize
from pymongo import MongoClient, ASCENDING
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

mongo_client_uri = env.get_airflow_env_var('MONGODB_AUTODIALER_URI')
logger = QuintoAndarLogger('Autodialer_ETL')
dummy_dt = '2018-01-01'


class Autodialer_ETL(object):
    def __init__(self, bucket_name, execution_date=None):
        self.s3_bucket = bucket_name
        self.execution_date = execution_date

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
        BaseETL.csv_to_s3(data=df, bucket=self.s3_bucket, filename=path)

    @logger
    def __mongo_connect(self, document_type):
        if document_type == 'task_references':
            return self.db.taskReferences
        if document_type == 'task_reference_inbound_event_histories':
            return self.db.taskReferenceInboundEventHistories
        if document_type == 'task_reference_outbound_history':
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

        athena_client = AthenaClient(self.s3_bucket)
        return athena_client.execute_file_query_and_return_dataframe(filename=filequery)

    @logger(exclude='df')
    def move_data_to_clean(self, document_type):
        path, dir_files = self.get_files_list(document_type)

        if len(dir_files) > 0:
            for i in dir_files:
                df = self.get_athena_data(document_type=document_type, filequery=i)
                logger.info('m=move_data_to_clean, file={}, msg=Query executed.'.format(dir_files))

                # treat data
                df_treated = self.normalize_json_columns(df)

                dt = 'dt={}'.format(
                    dummy_dt if self.execution_date is None else self.execution_date.strftime('%Y-%m-%d'))
                key = 'clean/autodialer/{0}/{1}/file.parq'.format(document_type, dt)
                athena_client = AthenaClient(self.s3_bucket)
                athena_client.create_parquet_from_df(key=key, df=df_treated)
                logger.info('m=move_data_to_clean, key={}, msg=File created in s3.'.format(key))
        else:
            logger.error('m=move_data_to_clean, path={}, msg=No query file found.'.format(path))

    @logger
    def get_files_list(self, document_type):
        path = '{}/{}'.format(AUTODIALER_DATALAKE_QUERIES_DIR, document_type)
        return path, listdir(path)

    @logger(exclude='df')
    def normalize_json_columns(self, df):
        df.replace('', np.nan, inplace=True)

        df_treatment = df.head(1)
        df_treated = df

        for column in df_treatment:
            try:
                df[column] = df[column].apply(json.loads)
                df_concat = json_normalize(df[column])
                df_treated = pd.concat([df_treated, df_concat], axis=1, sort=False)
                df_treated.drop(column, axis=1, inplace=True)
                del df_concat
                logger.info('m=normalize_json_columns, column={}, msg=Json normalized'.format(str(column)))
            except:
                logger.info('m=normalize_json_columns, column={}, msg=Not Json'.format(str(column)))

        return df_treated


# document = task_references.find().sort("_id", DESCENDING).limit(1)
# json_list = ast.literal_eval(task_references.find_one())

# creating
autodialer = Autodialer_ETL('5a-datalake')

# raw
# df = autodialer.get_mongo_data('task_references')
# df['contactInfo'] = df['contactInfo'].apply(json.dumps)
# df['dialStatus'] = df['dialStatus'].apply(json.dumps)
# autodialer.dump_data_into_datalake(df, 'raw', 'task_references')
# df = autodialer.get_mongo_data('task_reference_inbound_event_histories')
# autodialer.dump_data_into_datalake(df, 'raw', 'task_reference_inbound_event_histories')
# df = autodialer.get_mongo_data('task_reference_outbound_history')
# autodialer.dump_data_into_datalake(df, 'raw', 'task_reference_outbound_history')

# clean
# df = autodialer.get_athena_data('task_references')
autodialer.move_data_to_clean('task_references')
