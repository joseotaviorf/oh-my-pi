import pandas as pd
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags.util import environment as env
from pymongo import MongoClient, DESCENDING
from qa_python_utils import QuintoAndarLogger

mongo_client_uri = env.get_airflow_env_var('MONGODB_AUTODIALER_URI')
logger = QuintoAndarLogger('Agent')


class Autodialer_ETL(object):
    def __init__(self, bucket_name):
        self.bucket_datalake = bucket_name
        try:
            self.client = MongoClient(mongo_client_uri)
        except Exception as ex:
            raise Exception('m=,error={}, msg=Could not connect to mongo'.format(ex))

        self.db = self.client.autodialer

    # task references
    def get_task_references_data(self, execution_date=None):
        mongo_db = self.mongo_connect(document_type='taskReferences')
        raw_data = self.get_data(mongo_db, execution_date)
        return raw_data

    def dump_task_references_data(self, df, execution_date=None):
        dt = 'dt={}'.format('2018-01-01' if execution_date is None else execution_date.strftime('%Y-%m-%d'))
        self.df_to_s3(df, path='raw/autodialer/task_references/{}/tr.csv'.format(dt))

    # tools
    def df_to_s3(self, df, path):
        BaseETL.csv_to_s3(data=df, bucket=self.bucket_datalake, filename=path)

    def mongo_connect(self, document_type):
        # db.collection_names()
        if document_type == 'taskReferences':
            return self.db.taskReferences
        else:
            raise ValueError('m=connect, document_type={}, msg=Invalid document type.'.format(document_type))

    def get_data(self, mongo_db, execution_date):
        documents = []
        filter = None if execution_date is not None else ''

        documents = mongo_db.find().sort("_id", DESCENDING)
        return pd.DataFrame(list(documents))


# document = task_references.find().sort("_id", DESCENDING).limit(1)
# json_list = ast.literal_eval(task_references.find_one())


autodialer = Autodialer_ETL('5a-datalake')
df = autodialer.get_task_references_data()
autodialer.dump_task_references_data(df)
