import gzip
import json
import re
from abc import abstractmethod
from io import BytesIO

import boto3
from createsend import CreateSend, Client, Campaign
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL

logger = QuintoAndarLogger('CampaignMonitorCampaign')


class CampaignMonitorCampaign(object):
    S3_PATH_PREFIX = {
        'raw': 'raw/campaign_monitor/campaigns'
    }

    @logger(exclude='cm_auth')
    def __init__(self, s3_bucket, cm_auth, _type, execution_date):
        self.auth = {'api_key': cm_auth['api_key']}

        cs = CreateSend(self.auth)
        cs.user_agent = cm_auth['user_agent']
        self.client = Client(self.auth, cm_auth['client_id'])

        self.s3_bucket = s3_bucket
        self.s3_resource = boto3.resource('s3')
        self.athena_client = AthenaClient(s3_bucket)

        self._type = _type
        self.formatted_date = execution_date.strftime('%Y-%m-%d 00:00')
        self.epoch_date = execution_date.strftime('%s')

    # abstract methods
    @abstractmethod
    def request_campaign_data(self):
        logger.error('m=request_campaign_data, msg=method not implemented')
        raise Exception

    @abstractmethod
    def get_json_fields(self):
        logger.error('m=get_json_fields, msg=method not implemented')
        raise Exception

    # static methods
    @staticmethod
    @logger
    def _build_full_params(page=1, default_page_size=1000, order_field='email', order_direction='asc'):
        return {
            'page': page,
            'page_size': default_page_size,
            'order_field': order_field,
            'order_direction': order_direction
        }

    @staticmethod
    @logger
    def _build_incremental_params(_date, page=1, default_page_size=1000, order_field='date', order_direction='asc'):
        return {
            'date': _date,
            'page': page,
            'page_size': default_page_size,
            'order_field': order_field,
            'order_direction': order_direction
        }

    # instance methods
    @logger
    def _delete_old_files(self):
        key = '{}/campaign_id='.format(CampaignMonitorCampaign.S3_PATH_PREFIX['raw'])
        s3_bucket_obj = self.s3_resource.Bucket(self.s3_bucket)

        _files = (s3_bucket_obj
                  .objects
                  .filter(Prefix=key)
                  .all())

        key_files = [f.key for f in list(_files)]
        obj_keys = filter(re.compile(r'{}/data_\d+-\d+\.gz'.format(self._type)).search, key_files)
        for _obj_key in obj_keys:
            # because the API only allows a start or end date, the file deletion should not consider past data
            epoch_report_date = re.search(r'/{}/data_(\d+)-\d+\.gz'.format(self._type), _obj_key).group(1)
            if int(epoch_report_date) < self.epoch_date:
                continue

            response = (s3_bucket_obj
                        .objects
                        .filter(Prefix=_obj_key)
                        .delete())

            if (response is None or
                    len(response) == 0 or
                    'ResponseMetadata' not in response[0] or
                    'HTTPStatusCode' not in response[0]['ResponseMetadata'] or
                    response[0]['ResponseMetadata']['HTTPStatusCode'] != 200):
                logger.error('m=_exclude_old_files, key={}, msg=error deleting files from S3'.format(key))
                raise Exception

    @logger(exclude='result_gen')
    def _build_objs_and_send_to_s3(self, result_gen, json_fields):
        campaign_ids = []
        for result_dict in result_gen:
            json_result = self.__build_json_response(
                cm_obj=result_dict['result'],
                json_fields=json_fields
            )

            self.__save_to_s3(
                json_list=json_result,
                file_path='{}/{}/campaign_id={}/data_{}-{}.gz'.format(
                    CampaignMonitorCampaign.S3_PATH_PREFIX['raw'],
                    self._type,
                    result_dict['campaign_id'],
                    self.epoch_date,
                    result_dict['page']
                )
            )

            # list used to skip multiple partition upserts throughout the possible paging and different report types
            campaign_ids.append(result_dict['campaign_id'])

        for campaign_id in campaign_ids:
            # use of 'upsert' instead of 'add' partition method to contemplate cases where files are not longer in S3
            # it shouldn't have, so this is just a precaution
            self.athena_client.upsert_single_partition(
                bucket_folder_path='{}/{}/{}'.format(self.s3_bucket,
                                                     CampaignMonitorCampaign.S3_PATH_PREFIX['raw'],
                                                     self._type),
                database='datalake_raw',
                table='campaignmonitor_campaign_{}'.format(self._type),
                partition_name='campaign_id',
                partition_value=campaign_id
            )

    @logger(exclude='cm_obj')
    def __build_json_response(self, cm_obj, json_fields):
        if cm_obj is None:
            logger.error('m=__build_json_response, msg=cm_obj is none')
            raise Exception

        logger.info('m=__build_json_response, msg=building json item list')
        _json = []
        for _obj in cm_obj.Results:
            json_item = self.__build_json_item(
                _obj=_obj,
                json_fields=json_fields
            )
            _json.append(json_item)

        logger.info('m=__build_json_response, msg=json item list built successfully')
        return _json

    def __build_json_item(self, _obj, json_fields):
        _json_item = {}
        for json_field in json_fields:
            _json_item[json_field] = (getattr(_obj, json_field)).encode('utf-8')

        return _json_item

    @logger(exclude='json_list')
    def __save_to_s3(self, json_list, file_path):
        logger.info('m=__save_to_s3, msg=gzipping json_list')
        gz_body = BytesIO()
        with gzip.GzipFile(fileobj=gz_body, mode='w') as fp:
            for row in json_list:
                fp.write(json.dumps(row))
                fp.write('\n')

        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=self.s3_bucket,
            file_path=file_path
        )

        logger.info('m=__save_to_s3, file_path={}, msg=_json sent to s3'.format(file_path))
        gz_body.flush()

    @logger
    def _request_incremental_campaign_data(self):
        return self.__request_campaign_data(
            params_dict=CampaignMonitorCampaign._build_incremental_params(_date=self.formatted_date)
        )

    @logger
    def _request_full_campaign_data(self):
        return self.__request_campaign_data(
            params_dict=CampaignMonitorCampaign._build_full_params()
        )

    @logger
    def __get_campaign_max_pages_for_obj_type(self, campaign_id, params_dict):
        campaign = Campaign(self.auth, campaign_id)
        result = getattr(campaign, self._type)(**params_dict)

        if result is None:
            logger.error(
                'm=__get_campaign_obj_type_max_pages, campaign_id={}, params_dict={}, msg=result is none'.format(
                    campaign_id, params_dict))
            return -1

        return result.NumberOfPages

    @logger
    def __request_campaign_data(self, params_dict):
        for client_campaign in self.client.campaigns():
            logger.info('m=request_campaign_data, campaign_id={}'.format(client_campaign.CampaignID))

            campaign = Campaign(self.auth, client_campaign.CampaignID)
            max_pages = self.__get_campaign_max_pages_for_obj_type(
                campaign_id=campaign.campaign_id,
                params_dict=params_dict
            )

            if max_pages == -1:
                logger.error(
                    'm=__get_campaign_obj_type_max_pages, campaign_id={}, msg=result is none'.format(
                        campaign.campaign_id))
                raise Exception

            if max_pages == 0:
                logger.info('m=__request_campaign_data, campaign_id={}, msg=empty result'.format(campaign.campaign_id))
                continue

            self.__save_campaign(client_campaign)

            current_page = 0
            while current_page < max_pages:
                current_page += 1

                result = getattr(campaign, self._type)(**params_dict)
                params_dict['page'] = current_page

                yield {
                    'result': result,
                    'campaign_id': campaign.campaign_id,
                    'page': current_page
                }

    @logger
    def __save_campaign(self, client_campaign):
        campaign_json = {
            'CampaignID': client_campaign.CampaignID,
            'FromEmail': client_campaign.FromEmail,
            'FromName': client_campaign.FromName,
            'Name': client_campaign.Name,
            'ReplyTo': client_campaign.ReplyTo,
            'Subject': client_campaign.Subject,
            'WebVersionTextURL': client_campaign.WebVersionTextURL,
            'WebVersionURL': client_campaign.WebVersionURL,
        }

        self.__save_to_s3(
            json_list=[campaign_json],
            file_path='{}/campaigns/{}.gz'.format(CampaignMonitorCampaign.S3_PATH_PREFIX['raw'],
                                                  campaign_json['CampaignID'])
        )
