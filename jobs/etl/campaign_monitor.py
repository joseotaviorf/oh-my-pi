import gzip
from io import BytesIO
import json
import logging
import os
import sys
from datetime import datetime

from createsend import CreateSend, Client, Campaign
from jobs.base.base_etl import BaseETL
from qa_python_utils.aws.athena import AthenaClient

logging.basicConfig(level=logging.INFO)
_logger = logging.getLogger(__name__)

args = sys.argv

bucket_datalake = os.environ['bi-datalake-forno-s3-bucket']
cm_auth = json.loads(os.environ['campaign-monitor-auth'])

CAMPAIGN_DEFAULT_PAGE_SIZE = 1000
DATABASE = 'datalake_raw'


class CampaignMonitor(object):
    def __init__(self):
        self.auth = {'api_key': cm_auth['api_key']}
        cs = CreateSend(self.auth)
        cs.user_agent = cm_auth['user_agent']
        self.clients = cs.clients()
        self.execution_date = str(datetime.strptime(args[2], "%Y-%m-%d %H:%M:%S").date())

        self.athena_client = AthenaClient(bucket_datalake)

        self.full_params = self.__build_campaign_full_params()
        self.incremental_params = self.__build_campaign_incremental_params()

    def __build_campaign_full_params(self):
        return {
            'pagesize': CAMPAIGN_DEFAULT_PAGE_SIZE,
            'orderfield': 'email',
            'orderdirection': 'asc'
        }

    def __build_campaign_incremental_params(self):
        return {
            'date': args[2],
            'pagesize': CAMPAIGN_DEFAULT_PAGE_SIZE,
            'orderfield': 'date',
            'orderdirection': 'asc'
        }

    def request_campaign_data(self):
        _logger.info('m=request_campaign_data')

        if len(self.clients) != 1:
            _logger.info('m=request_campaign_data clients length={}'.format(len(self.clients)))
        else:
            cl = self.clients[0]
            _logger.info('m=request_campaign_data cl_name={}, cl_id={}'.format(cl.Name, cl.ClientID))

            client = Client(self.auth, cl.ClientID)
            client.campaigns()
            for cm in client.campaigns():
                _logger.info('m=request_campaign_data campaign_id={}'.format(cm.CampaignID))

                campaign = Campaign(self.auth, cm.CampaignID)
                self.__request_recipients_data(campaign)
                self.__request_bounces_data(campaign)
                self.__request_opens_data(campaign)
                self.__request_clicks_data(campaign)
                self.__request_unsubscribes_data(campaign)
                self.__request_spam_data(campaign)

            self.athena_client.msck_repair_table(DATABASE, 'recipients')
            self.athena_client.msck_repair_table(DATABASE, 'bounces')
            self.athena_client.msck_repair_table(DATABASE, 'opens')
            self.athena_client.msck_repair_table(DATABASE, 'clicks')
            self.athena_client.msck_repair_table(DATABASE, 'unsubscribes')
            self.athena_client.msck_repair_table(DATABASE, 'spam')

    def __request_recipients_data(self, campaign):
        self.__request_incremental_data(campaign, 'recipients', self.full_params)

    def __request_bounces_data(self, campaign):
        self.__request_incremental_data(campaign, 'bounces', self.incremental_params)

    def __request_opens_data(self, campaign):
        self.__request_incremental_data(campaign, 'opens', self.incremental_params)

    def __request_clicks_data(self, campaign):
        self.__request_incremental_data(campaign, 'clicks', self.incremental_params)

    def __request_unsubscribes_data(self, campaign):
        self.__request_incremental_data(campaign, 'unsubscribes', self.incremental_params)

    def __request_spam_data(self, campaign):
        self.__request_incremental_data(campaign, 'spam', self.incremental_params)

    def __request_incremental_data(self, campaign, object_type, params):
        _logger.info(
            'm=__request_incremental_data, campaign_id={}, object_type={}'.format(campaign.campaign_id, object_type))

        j = campaign._get("/campaigns/{}/{}.json".format(campaign.campaign_id, object_type), params=params)
        result = json.loads(j.decode('utf-8'))

        gz_body = BytesIO()
        with gzip.GzipFile(fileobj=gz_body, mode='w') as fp:
            for _ in range(0, result['NumberOfPages']):
                for r in result['Results']:
                    fp.write(json.dumps(r))
                    fp.write('\n')

        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=bucket_datalake,
            file_path='raw/campaign_monitor/{0}/campaign_id={1}/dt={2}/{0}.gz'.format(object_type, campaign.campaign_id,
                                                                                      self.execution_date)
        )

    def request_transactional_data(self):
        _logger.info('m=request_transactional_data')

        if len(self.clients) != 1:
            _logger.info('m=request_transactional_data clients length={}'.format(len(self.clients)))
        else:
            cl = self.clients[0]
            _logger.info('m=request_transactional_data cl_name={}, cl_id={}'.format(cl.Name, cl.ClientID))

            client = Client(self.auth, cl.ClientID)
            client.campaigns()
            for cm in client.campaigns():
                _logger.info('m=request_transactional_data campaign_id={}'.format(cm.CampaignID))


if __name__ == '__main__':
    campaign_monitor = CampaignMonitor()

    if args[1] == 'request_campaign_data':
        campaign_monitor.request_campaign_data()
    if args[1] == 'request_transactional_data':
        campaign_monitor.request_transactional_data()
    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))
