import json

import requests
from qa_python_utils.default_logger import logger, _logger


class PowerBIClient(object):
    def __init__(self, power_bi_auth, power_bi_schema, workspace_name, dataset_name):
        self.PWBI_SCHEMA = json.loads(power_bi_schema)
        self.PWBI_AUTH = json.loads(power_bi_auth)
        self.group_id, self.dataset_id = self.__get_powerbi_ids(workspace_name, dataset_name)
        self.URL = 'https://api.powerbi.com/v1.0/myorg/groups/{0}/datasets/{1}/refreshes'.format(self.group_id,
                                                                                                 self.dataset_id)

    @logger
    def __get_powerbi_ids(self, workspace_name, dataset_name):
        try:
            for w in self.PWBI_SCHEMA['Workspaces']:
                if w['Workspace'] == workspace_name:
                    for ds in w['Datasets']:
                        if ds['Dataset_Name'] == dataset_name:
                            return w['Workspace_Id'], ds['Dataset_Id']
                    raise RuntimeError(
                        'm=__get_powerbi_ids, workspace_name={0}, dataset_name={1}, power_bi_json_schema={2},'
                        ' msg=Dataset not found in PowerBI json schema.'.format(workspace_name, dataset_name,
                                                                                self.PWBI_SCHEMA))
            raise RuntimeError(
                'm=__get_powerbi_ids, workspace_name={0}, power_bi_json_schema={1},'
                ' msg=Workspace not found in PowerBI json schema.'.format(workspace_name, self.PWBI_SCHEMA))

        except Exception as e:
            raise Exception(
                'm=__get_powerbi_ids, workspace_name={0}, dataset_name={1}, power_bi_json_schema={2},'
                ' exception={3}, msg=PowerBI json schema not matching the expected patttern.'.format(workspace_name,
                                                                                                     dataset_name,
                                                                                                     self.PWBI_SCHEMA,
                                                                                                     e.message))

    @logger
    def get_refresh_history(self):
        authorization_header = 'Bearer {}'.format(self.__get_access_token(self.PWBI_AUTH.get('PWBI_REFRESH_TOKEN'),
                                                                          self.PWBI_AUTH.get('PWBI_CLIENT_ID_KEY'),
                                                                          self.PWBI_AUTH.get('PWBI_SECRET_KEY')))
        try:
            response = requests.get(self.URL, headers={'Authorization': authorization_header})
        except Exception as e:
            raise Exception(
                'm=trigger_refresh, exception={}, msg=Unable to get refresh history data from server.'.format(
                    e.message))

        _logger.info('m=get_refresh_history, response_status={}, msg=Refresh history successfully gotten.'.format(
            response.status_code))

        return response.json()

    @logger
    def trigger_refresh(self):
        authorization_header = 'Bearer {}'.format(self.__get_access_token(self.PWBI_AUTH.get('PWBI_REFRESH_TOKEN'),
                                                                          self.PWBI_AUTH.get('PWBI_CLIENT_ID_KEY'),
                                                                          self.PWBI_AUTH.get('PWBI_SECRET_KEY')))
        try:
            response = requests.post(self.URL, headers={'Authorization': authorization_header})
        except Exception as e:
            raise Exception(
                'm=trigger_refresh, exception={}, msg=Unable to send data to server.'.format(e.message))

        if response.status_code not in (requests.codes.ok, requests.codes.accepted):
            raise Exception('m=trigger_refresh, response_status={}, msg=Could not trigger PowerBI refresh.'.format(
                response.status_code))

        _logger.info('m=trigger_refresh, response_status={}, msg=Refresh request sent to PowerBI webapp.'.format(
            response.status_code))

    @logger(exclude=['refresh_token', 'client_id', 'client_secret'])
    def __get_access_token(self, refresh_token, client_id, client_secret):
        payload = {
            'grant_type': 'refresh_token',
            'resource': 'https://analysis.windows.net/powerbi/api',
            'client_id': client_id,
            'client_secret': client_secret,
            'refresh_token': refresh_token
        }

        try:
            response = requests.post("https://login.microsoftonline.com/common/oauth2/token", data=payload).json()
        except Exception as e:
            raise Exception('m=__get_access_token, exception={}, msg=Unable to get access token.'.format(e.message))

        _logger.info('m=__get_access_token, msg=Access token successfully gotten.')

        return response.get('access_token')
