import io
import requests

from bietlejuice.jobs.base.base_etl import BaseETL


class MailchimpExportApi(BaseETL):

    def __init__(self):#, api_key, secret_key):
        self.API_KEY = "14476e1488da7621f694a7d647274493-us14" #api_key

    def get_files_from_extract_api(self, category, start_date, end_date):
        url = 'https://us14.api.mailchimp.com/3.0/{}'
        url_full = url.format(category)

        if category == 'campaigns':
            payload = {'count': 1000, 'since_create_time': start_date, 'before_create_time': end_date}
        elif category == 'lists':
            payload = {'count': 1000, 'since_date_created': start_date, 'before_date_created': end_date}
        elif category == 'templates':
            payload = {'count': 1000, 'since_date_created': start_date}
        else:
            payload = {'count': 1000}

        r = requests.get(url_full, params=payload, auth=(self.API_KEY, self.API_KEY))
        file_stream = None
        print('Keys: {} - URL: {} - STATUS_CODE: {}'.format(self.API_KEY, url_full, r.status_code))
        if r.status_code == 200:
            file_stream = io.BytesIO(r.content)
        return file_stream


if __name__ == '__main__':

    print('START')
    mc = MailchimpExportApi()
    print('CREATED')
    file = mc.get_files_from_extract_api('campaigns', '2018-05-02T00:00:00+00:00', '2018-05-02T23:59:59+00:00')
    print('GENERATED')
