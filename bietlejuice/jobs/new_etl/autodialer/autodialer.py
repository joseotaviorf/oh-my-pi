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

    def get_task_references_data(self, execution_date=None):
        mongo_db = self.mongo_connect(document_type='taskReferences')
        raw_data = self.get_data(mongo_db, execution_date)
        len(raw_data)
        print(len(raw_data))
        print(len(raw_data))

    def mongo_connect(self, document_type):
        # db.collection_names()
        if document_type == 'taskReferences':
            return self.db.taskReferences
        else:
            raise ValueError('m=connect, documen_type={}, msg=Invalid document type.'.format(document_type))

    def get_data(self, mongo_db, execution_date):
        documents = []
        filter = None if execution_date is not None else ''

        documents = mongo_db.find().sort("_id", DESCENDING)
        return documents


# document = task_references.find().sort("_id", DESCENDING).limit(1)
# json_list = ast.literal_eval(task_references.find_one())


autodialer = Autodialer_ETL('5a-datalake')
autodialer.get_task_references_data()
