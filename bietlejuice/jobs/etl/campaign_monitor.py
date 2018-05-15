import gzip
import io
import json
import os
import re
import sys
import time
from collections import OrderedDict
from datetime import datetime
from io import BytesIO

import boto3
import pandas as pd
# createsend==4.2.1
from createsend import CreateSend, Client, Transactional, Campaign
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger

from bietlejuice.jobs.base.base_etl import BaseETL

args = sys.argv
today_tmsp = datetime.strptime(args[2], "%Y-%m-%d %H:%M:%S")
today = str(today_tmsp.date())

bucket_datalake = os.environ['bi-datalake-s3-bucket']
cm_auth = json.loads(os.environ['campaign-monitor-auth'])

DEFAULT_PAGE_SIZE = 1000
DATABASE = 'datalake_raw'

CAMPAIGN_FIRST_MESSAGE = {
    'homes': 'b3151e06-9246-11e7-a995-de6808d5a69c'
}

CAMPAIGN_SMART_EMAIL_ID = {
    'homes': '3c4c3e77-1f62-444b-b6bc-1a8c09192b16'
}


class CampaignMonitor(object):
    def __init__(self):
        self.auth = {'api_key': cm_auth['api_key']}
        cs = CreateSend(self.auth)
        cs.user_agent = cm_auth['user_agent']
        self.clients = cs.clients()

        self.athena_client = AthenaClient(bucket_datalake)
        self.s3_client = boto3.resource('s3')

        self.full_params = self.__build_full_params()
        self.incremental_params = self.__build_incremental_params()

    def __build_full_params(self):
        return {
            'pagesize': DEFAULT_PAGE_SIZE,
            'orderfield': 'email',
            'orderdirection': 'asc'
        }

    def __build_incremental_params(self):
        return {
            'date': args[2],
            'pagesize': DEFAULT_PAGE_SIZE,
            'orderfield': 'date',
            'orderdirection': 'asc'
        }

    def save_json_messages_to_s3(self, json_messages, key, last_message):
        df = pd.DataFrame(json_messages)
        df = df.astype(object).where(pd.notnull(df), None)

        datalake = self.s3_client.Bucket(bucket_datalake)
        gz_body = io.BytesIO()
        with gzip.GzipFile(fileobj=gz_body, mode='w') as fp:
            for row in df.iterrows():
                row[1].to_json(fp, date_format='iso', date_unit='ms')
                fp.write('\n')

        datalake.put_object(Body=gz_body.getvalue(), Key='{}/{}.gz'.format(key, last_message))
        gz_body.flush()

    @logger
    def request_project_transactional_data(self, project_name, project_first_message, project_smart_email_id):
        client = self.__get_client()
        if not client:
            return

        transactional = Transactional(self.auth, client_id=client.client_id)
        last_message = project_first_message
        homes_params = {
            'clientID': client.client_id,
            'smartEmailID': project_smart_email_id,
            'count': 200
        }

        count = 0
        json_messages = []
        key = 'raw/campaign_monitor/transactional_messages/project={}'.format(project_name)
        while last_message:
            result = transactional._get('/transactional/messages', params=homes_params)
            messages = json.loads(result.decode('utf-8'))
            last_message = None
            for msg in messages:
                _logger.info('m=request_project_transactional_data, msg=processing msg \'{}\''.format(msg['MessageID']))
                last_message = msg['MessageID']

                try:
                    smart_email_details = transactional._get(
                        '/transactional/messages/{}?statistics={}'.format(last_message, True))
                except Exception:
                    _logger.warn('m=request_project_transactional_data, msg=too many requests; waiting...')
                    # hold a little to continue hitting the api
                    time.sleep(300)
                    smart_email_details = transactional._get(
                        '/transactional/messages/{}?statistics={}'.format(last_message, True))

                details_json = json.loads(smart_email_details.decode('utf-8'))
                details_json['dt'] = today
                json_messages.append(details_json)

            _logger.info(
                'm=request_project_transactional_data, key={}, last_message={}, msg=saving into s3'.format(
                    key, last_message))
            self.save_json_messages_to_s3(json_messages, key, last_message)
            count += 1

            if last_message != project_first_message:
                homes_params['sentBeforeID'] = last_message
            else:
                last_message = None

        _logger.info('m=request_project_transactional_data, final_count={}'.format(count))
        self.athena_client.upsert_single_partition(
            bucket_folder_path='{}/raw/campaign_monitor/transactional_messages'.format(bucket_datalake),
            database='datalake_raw',
            table='cm_transactional_messages',
            partition_name='project',
            partition_value='homes'
        )

    @logger
    def request_homes_transactional_data(self):
        self.request_project_transactional_data(
            project_name='homes',
            project_first_message=CAMPAIGN_FIRST_MESSAGE['homes'],
            project_smart_email_id=CAMPAIGN_SMART_EMAIL_ID['homes']
        )

    @logger
    def deduplicate_homes_transactional_data(self):
        deduplication_query = './bietlejuice/db/2.datalake/queries/transactional_messages.sql'
        df = self.athena_client.execute_file_query_and_return_dataframe(deduplication_query, 'homes')

        self.athena_client.create_parquet_from_df(
            key='clean/campaign_monitor/transactional_messages/project=homes/messages.parq',
            df=df,
            raw_columns=OrderedDict([
                ('canberesent', str),
                ('subject', str),
                ('email_from', str),
                ('email_to', str),
                ('messageid', str),
                ('sentat', str),
                ('smartemailid', str),
                ('status', str),
                ('totalclicks', str),
                ('totalopens', str),
                ('property_email_id', str),
                ('rn_property_email_id', str),
                ('url', str),
                ('property_link_id', str),
                ('first_opened_date', str),
                ('date', str),
                ('city', str),
                ('countrycode', str),
                ('countryname', str),
                ('region', str),
                ('longitude', str),
                ('latitude', str),
                ('opened', str),
                ('clicked', str)
            ]),
            clean_columns=OrderedDict([
                ('can_be_resent', str),
                ('subject', str),
                ('email_from', str),
                ('email_to', str),
                ('message_id', str),
                ('sent_at', str),
                ('smart_email_id', str),
                ('status', str),
                ('total_clicks', str),
                ('total_opens', str),
                ('property_email_id', str),
                ('rn_property_email_id', str),
                ('url', str),
                ('property_link_id', str),
                ('first_opened_date', str),
                ('date', str),
                ('city', str),
                ('country_code', str),
                ('country_name', str),
                ('region', str),
                ('long', str),
                ('lat', str),
                ('opened', str),
                ('clicked', str)
            ])
        )

        self.athena_client.upsert_single_partition(
            bucket_folder_path='{}/clean/campaign_monitor/transactional_messages'.format(bucket_datalake),
            database='datalake_clean',
            table='transactional_messages',
            partition_name='project',
            partition_value='homes'
        )

    @logger
    def request_transactional_data(self):
        client = self.__get_client()
        if not client:
            return

        transactional = Transactional(self.auth, client_id=client.client_id)
        last_message = self.__get_last_message_from_s3()

        count = 0
        json_messages = []
        key = 'raw/campaign_monitor/transactional_messages'
        max_sent_at = None
        max_last_message_id = None
        last_sent_at = None
        while last_message:
            if last_sent_at and datetime.strptime(last_sent_at[:-6], '%Y-%m-%dT%H:%M:%S') > today_tmsp:
                last_message = None
                continue

            result = transactional._get("/transactional/messages", params={
                'clientID': client.client_id,
                'sentAfterID': last_message,
                'count': 200
            })

            messages = json.loads(result.decode('utf-8'))
            last_message = None
            for msg in messages:
                _logger.info('m=request_transactional_data, msg=processing msg \'{}\''.format(msg['MessageID']))
                last_message = msg['MessageID']
                last_sent_at = msg['SentAt']
                if (max_sent_at and max_sent_at < last_sent_at) \
                        or not max_sent_at:
                    max_sent_at = last_sent_at
                    max_last_message_id = last_message

                try:
                    smart_email_details = transactional._get(
                        '/transactional/messages/{}?statistics={}'.format(last_message, True))
                except Exception:
                    _logger.warn('m=request_transactional_data, msg=too many requests; waiting...')
                    # hold a little to continue hitting the api
                    time.sleep(300)
                    smart_email_details = transactional._get(
                        "/transactional/messages/%s?statistics=%s" % (last_message, True))

                json_messages.append(json.loads(smart_email_details.decode('utf-8')))

            _logger.info(
                'm=request_transactional_data, key={}, last_message={}, msg=saving into s3'.format(key, last_message))
            self.save_json_messages_to_s3(json_messages, key, last_message)
            count += 1

            # hold a little to continue hitting the api
            _logger.info('m=request_transactional_data, msg=sleeping for 60 seconds...')
            time.sleep(30)

        _logger.info('m=request_transactional_data, final_count={}'.format(count))
        if max_sent_at and max_last_message_id:
            self.__save_last_message_to_s3(max_last_message_id)

    @logger
    def __get_last_message_from_s3(self):
        last_message_object = self.s3_client.Object(bucket_datalake, 'raw/campaign_monitor/transactional_last_message')
        raw_string = last_message_object.get()['Body'].read()

        try:
            return re.search('\w{8}-(\w{4}-){3}\w{12}', raw_string).group()
        except Exception:
            _logger.error(
                'm=__get_last_message_from_s3, raw_string={}, msg=couldn\'t find message id'.format(raw_string))
            raise

    @logger
    def __save_last_message_to_s3(self, max_last_message_id):
        last_message_object = self.s3_client.Object(bucket_datalake, 'raw/campaign_monitor/transactional_last_message')
        last_message_object.put(Body=max_last_message_id)

    @logger
    def __get_client(self):
        if len(self.clients) != 1:
            _logger.info('m=__get_client, clients_length={}'.format(len(self.clients)))
            return None

        cl = self.clients[0]
        _logger.info('m=__get_client, cl_name={}, cl_id={}'.format(cl.Name, cl.ClientID))
        return Client(self.auth, cl.ClientID)

    @logger
    def request_campaign_data(self):
        client = self.__get_client()
        if not client:
            return

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
        self.__request_incremental_campaign_data(campaign, 'recipients', self.full_params)

    def __request_bounces_data(self, campaign):
        self.__request_incremental_campaign_data(campaign, 'bounces', self.incremental_params)

    def __request_opens_data(self, campaign):
        self.__request_incremental_campaign_data(campaign, 'opens', self.incremental_params)

    def __request_clicks_data(self, campaign):
        self.__request_incremental_campaign_data(campaign, 'clicks', self.incremental_params)

    def __request_unsubscribes_data(self, campaign):
        self.__request_incremental_campaign_data(campaign, 'unsubscribes', self.incremental_params)

    def __request_spam_data(self, campaign):
        self.__request_incremental_campaign_data(campaign, 'spam', self.incremental_params)

    def __request_incremental_campaign_data(self, campaign, object_type, params):
        _logger.info(
            'm=__request_incremental_campaign_data, campaign_id={}, object_type={}'.format(campaign.campaign_id,
                                                                                           object_type))

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
            file_path='raw/campaign_monitor/campaigns/{0}/campaign_id={1}/dt={2}/{0}.gz'.format(object_type,
                                                                                                campaign.campaign_id,
                                                                                                today)
        )


if __name__ == '__main__':
    campaign_monitor = CampaignMonitor()

    if args[1] == 'request_campaign_data':
        campaign_monitor.request_campaign_data()
    elif args[1] == 'request_transactional_data':
        campaign_monitor.request_transactional_data()
    elif args[1] == 'request_homes_transactional_data':
        campaign_monitor.request_homes_transactional_data()
    elif args[1] == 'deduplicate_homes_transactional_data':
        campaign_monitor.deduplicate_homes_transactional_data()
    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))
