import pandas as pd
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags.util import environment as env
from pymongo import MongoClient, ASCENDING
from qa_python_utils import QuintoAndarLogger

mongo_client_uri = env.get_airflow_env_var('MONGODB_AUTODIALER_URI')
logger = QuintoAndarLogger('Agent')
dummy_dt = '2018-01-01'


class Autodialer_ETL(object):
    def __init__(self, bucket_name):
        self.bucket_datalake = bucket_name

        try:
            self.client = MongoClient(mongo_client_uri)
            self.db = self.client.autodialer
        except Exception as ex:
            raise Exception('m=,error={}, msg=Could not connect to mongo'.format(ex))

    # task references
    @logger
    def get_db_data(self, document_type, execution_date=None):
        mongo_db = self.mongo_connect(document_type=document_type)
        raw_data = self.get_data(mongo_db, execution_date)
        return raw_data

    @logger(exclude='df')
    def dump_data_into_datalake(self, df, document_type, execution_date=None):
        dt = 'dt={}'.format(dummy_dt if execution_date is None else execution_date.strftime('%Y-%m-%d'))
        self.df_to_s3(df, path='raw/autodialer/{0}/{1}/tr.csv'.format(document_type, dt))
        logger.info("m=dump_data_into_datalake, document_type={0},"
                    " execution_date={1},"
                    " df_length={2}, "
                    " msg=Df dumped into datalake!".format(document_type,
                                                           str(execution_date) if execution_date else 'None',
                                                           str(len(df))))

    # tools
    @logger(exclude='df')
    def df_to_s3(self, df, path):
        BaseETL.csv_to_s3(data=df, bucket=self.bucket_datalake, filename=path)

    @logger
    def mongo_connect(self, document_type):
        if document_type == 'task_references':
            return self.db.taskReferences
        if document_type == 'task_reference_inbound_event_histories':
            return self.db.taskReferenceInboundEventHistories
        if document_type == 'task_reference_outbound_history':
            return self.db.taskReferenceOutboundHistory
        else:
            raise ValueError('m=connect, document_type={}, msg=Invalid document type.'.format(document_type))

    @logger
    def get_data(self, mongo_db, execution_date):
        filter = None if execution_date is not None else ''

        documents = mongo_db.find().sort("_id", ASCENDING)
        return pd.DataFrame(list(documents))


# document = task_references.find().sort("_id", DESCENDING).limit(1)
# json_list = ast.literal_eval(task_references.find_one())


autodialer = Autodialer_ETL('5a-datalake')
df = autodialer.get_db_data('task_references')
autodialer.dump_data_into_datalake(df, 'task_references')
df = autodialer.get_db_data('task_reference_inbound_event_histories')
autodialer.dump_data_into_datalake(df, 'task_reference_inbound_event_histories')
df = autodialer.get_db_data('task_reference_outbound_history')
autodialer.dump_data_into_datalake(df, 'task_reference_outbound_history')
