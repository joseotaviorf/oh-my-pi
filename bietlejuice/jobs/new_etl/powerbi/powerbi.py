import json

import requests
from bietlejuice.jobs.dags.util import environment as env
from qa_python_utils.default_logger import logger

PWBI_CLIENT_ID_KEY = env.get_airflow_env_var('PWBI_CLIENT_ID_KEY')
PWBI_SECRET_KEY = env.get_airflow_env_var('PWBI_SECRET_KEY')
PWBI_REFRESH_TOKEN = env.get_airflow_env_var('PWBI_REFRESH_TOKEN')
PWBI_SCHEMA = env.get_airflow_env_var('PWBI_SCHEMA')


class PowerBIClient(object):
    def __init__(self, workspace_name, dataset_name):
        self.group_id, self.dataset_id = self.__get_powerbi_ids(workspace_name, dataset_name)
        self.URL = 'https://api.powerbi.com/v1.0/myorg/groups/{0}/datasets/{1}/refreshes'.format(self.group_id,
                                                                                                 self.dataset_id)

    @logger
    def __get_powerbi_ids(self, workspace_name, dataset_name):
        workspace_id = ''
        dataset_id = ''
        json_schema = json.loads(PWBI_SCHEMA)

        for w in json_schema['Workspaces']:
            if w['Workspace'] == workspace_name:
                workspace_id = w['Workspace_Id']
                for ds in w['Datasets']:
                    if ds['Dataset_Name'] == dataset_name:
                        dataset_id = ds['Dataset_Id']
                        break
                break

        return workspace_id, dataset_id

    @logger
    def get_refresh_history(self):
        authorization_header = 'Bearer %s' % self.__get_access_token(PWBI_REFRESH_TOKEN, PWBI_CLIENT_ID_KEY,
                                                                     PWBI_SECRET_KEY)
        try:
            response = requests.get(self.URL, headers={'Authorization': authorization_header})
        except Exception:
            raise Exception('Unable to retrieve data from server.')

        return json.dumps(json.loads(response.content))

    @logger
    def trigger_refresh(self):
        authorization_header = 'Bearer %s' % self.__get_access_token(PWBI_REFRESH_TOKEN, PWBI_CLIENT_ID_KEY,
                                                                     PWBI_SECRET_KEY)
        try:
            response = requests.post(self.URL, headers={'Authorization': authorization_header})
        except Exception:
            raise Exception('Unable to send data to server.')

        if response.status_code not in (requests.codes.ok, requests.codes.accepted):
            raise Exception('Could not trigger PowerBI refresh.')

    @logger(exclude=['refresh_token', 'client_id', 'client_secret'])
    def __get_access_token(self, refresh_token, client_id, client_secret):
        payload = {
            'grant_type': 'refresh_token',
            'resource': 'https://analysis.windows.net/powerbi/api',
            'client_id': client_id,
            'client_secret': client_secret,
            'refresh_token': refresh_token
        }

        response = requests.post("https://login.microsoftonline.com/common/oauth2/token", data=payload).json()
        return response.get('access_token')
