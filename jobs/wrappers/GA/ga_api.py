# coding=utf-8
import httplib2
import os
import json
from apiclient import discovery
from oauth2client.service_account import ServiceAccountCredentials


class GA_API(object):

    def __init__(self, account_name, property_name, profile_name):
        self.account_name = account_name
        self.property_name = property_name
        self.profile_name = profile_name

        scope = ['https://www.googleapis.com/auth/analytics.readonly']
        analytics_json = json.loads(os.environ['ANALYTICS_KEY_JSON'])
        credentials = ServiceAccountCredentials.from_json_keyfile_dict(analytics_json, scopes=scope)

        http = credentials.authorize(httplib2.Http())
        self.analytics = discovery.build('analytics', 'v3', http=http)

        accounts = self.analytics.management().accounts().list().execute()
        self.account = self._get_named_item(accounts, account_name)

        properties = self.analytics.management().webproperties().list(
            accountId=self.account).execute()
        self.property = self._get_named_item(properties, property_name)

        profiles = self.analytics.management().profiles().list(
            accountId=self.account, webPropertyId=self.property).execute()
        self.profile = self._get_named_item(profiles, profile_name)

    @staticmethod
    def _get_named_item(container, name):
        # import pdb; pdb.set_trace()
        for item in container['items']:
            if item['name'] == name:
                return item['id']
        print("no %s in " % name, [item["name"] for item in container["items"]])
        return None

    def get_query(self, max_results=5000, include_header = True, **params):
        all_rows = []
        start_index = 1
        header = None
        contains_sampling_data = None
        while True:

            ans = self.analytics.data().ga().get(
                ids='ga:' + self.profile,
                max_results=max_results,
                start_index=start_index,
                **params).execute()

            if contains_sampling_data is None:
                contains_sampling_data = ans['containsSampledData']

            if not header:
                header = [h['name'].replace('ga:', '') for h in ans['columnHeaders']]

            if include_header and header:
                all_rows.append(header)

            if ans.get('rows'):
                all_rows.extend(ans['rows'])
            start_index = ans['query']['start-index'] + ans['itemsPerPage']
            if start_index >= ans['totalResults']:
                break

        return all_rows, contains_sampling_data
