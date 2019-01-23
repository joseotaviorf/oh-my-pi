import json
from ast import literal_eval
from gzip import GzipFile
from io import BytesIO

import requests
from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl.marketing.marketing import Marketing

logger = QuintoAndarLogger('CriteoCampaigns')


class CriteoCampaigns(Marketing):
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'

    COLUMN_TYPE_MAP = {
        'marketing_criteo_campaigns': {
            'advertiser_name': str,
            'campaign_id': int,
            'campaign_name': str,
            'day': int,
            'currency': str,
            'clicks': int,
            'cost': float,
            'impressions': int,
            'Sales': int,
            'Audiencia': float,
            'Revenue': int,
            'comp_win': float,
            'cpc': float,

        }
    }

    def __init__(self, s3_bucket, execution_date, auth, account=None):
        super(CriteoCampaigns, self).__init__(s3_bucket, execution_date, 'criteo_campaigns', auth)
        self.client_id = auth['client_id']
        self.client_secret = auth['client_secret']

    def move_criteo_campaigns_to_raw(self):
        self.__save_to_s3(self.client_id, self.client_secret)

    def __get_token(self, client_id, client_secret):
        logger.info('m=__get_token')
        headers = {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
        }

        data = {
            'client_id': client_id,
            'client_secret': client_secret,
            'grant_type': 'client_credentials'
        }

        response = requests.post('https://api.criteo.com/marketing/oauth2/token', headers=headers, data=data)
        dic = literal_eval(response.text)
        auth_token = 'Bearer ' + dic['access_token']
        return auth_token

    def __make_request(self, client_id, client_secret):
        logger.info('m=__make_request')
        auth_token = self.__get_token(client_id, client_secret)

        headers = {
            'Content-Type': 'application/json',
            'Accept': 'application/octet-stream',
            'Authorization': auth_token,
        }

        body = {'reportType': 'CampaignPerformance',
                'startDate': '{}'.format(self.execution_date.strftime('%Y-%m-%d') + 'T00:00:59.000Z'),
                'endDate': '{}'.format(self.execution_date.strftime('%Y-%m-%d') + 'T23:59:00.000Z'),
                'dimensions': ['CampaignId', 'Day'],
                'metrics': ['Clicks', 'Displays', 'Audience', 'AdvertiserCost', 'SalesAllPc', 'RevenueGeneratedPc',
                            'OverallCompetitionWin', 'ECpc'],
                'format': 'json', 'timezone': 'GMT'}

        data = json.dumps(body)
        try:
            response = requests.post('https://api.criteo.com/marketing/v1/statistics', headers=headers, data=data)
            return response.text
        except requests.exceptions.RequestException as e:
            logger.error('m=__make_request, error message={}'.format(e))

    def __save_to_s3(self, client_id, client_secret):
        logger.info('m=__save_to_s3, client_id={}'.format(client_id))
        raw_json_data = self.__make_request(client_id, client_secret)

        gz_body = BytesIO()
        with GzipFile(fileobj=gz_body, mode='w') as fp:
            fp.write((json.dumps(raw_json_data, ensure_ascii=False)).encode('utf-8'))
            fp.write('\n')

        file_suffix = 'raw/marketing/criteo_campaigns/dt_extraction={}/data.gz'.format(
            self.execution_date.strftime('%Y-%m-%d'))

        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=self.s3_bucket,
            file_path=file_suffix
        )

        gz_body.seek(0)
        gz_body.flush()
