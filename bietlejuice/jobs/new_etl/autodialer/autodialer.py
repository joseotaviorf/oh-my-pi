import ast

from bietlejuice.jobs.dags.util import environment as env
from pymongo import MongoClient

mongo_client_uri = env.get_airflow_env_var('MONGODB_AUTODIALER_URI')
client = MongoClient(mongo_client_uri)
db = client.autodialer
# db.collection_names()
task_references = db.taskReferences

json_list = ast.literal_eval(task_references.find_one())
print(json_list)
