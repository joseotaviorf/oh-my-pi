import io
import petl
import requests
from jobs.base.base_etl import BaseETL, log


class AmplitudeExportApi(BaseETL):

    def __init__(self, api_key, secret_key):
        self.API_KEY = api_key
        self.SECRET_KEY = secret_key

    def get_files_from_extract_api(self, start_time, end_time):
        url = 'https://amplitude.com/api/2/export?start={}&end={}'
        url_full = url.format(start_time,end_time)
        r = requests.get(url_full , auth=(self.API_KEY, self.SECRET_KEY))
        file_stream = None
        print('Keys: {}, {} - URL: {} - STATUS_CODE: {}'.format(self.API_KEY, self.SECRET_KEY, url_full, r.status_code))
        if r.status_code == 200:
            file_stream = io.BytesIO(r.content)
        return file_stream

    def convert_to_tables(self, event_dicts):
        ev = petl.fromdicts(event_dicts)
        user_properties = None
        event_properties = None
        groups = None
        data = None
        event_id = 0
        for r in ev:
            if r == ev[0]:
                continue  # discard header
            user_properties = self.get_table_from_json_child(ev,'user_properties', 'event_id', event_id)
            event_properties = self.get_table_from_json_child(ev,'event_properties', 'event_id', event_id)
            groups = self.get_table_from_json_child(ev, 'groups', 'event_id', event_id)
            data = self.get_table_from_json_child(ev, 'data', 'event_id', event_id)
            event_id += 1

        return ev, user_properties, event_properties, groups, data
