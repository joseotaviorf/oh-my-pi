import json
from airflow.models import Variable


with open('airflow_python/local_env.json', 'r') as envs:
    deserializable_envs = json.loads(envs.read())
    for env in deserializable_envs:
        Variable.set(env, deserializable_envs[env])
