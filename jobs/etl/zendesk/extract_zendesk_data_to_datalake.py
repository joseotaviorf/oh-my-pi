import json
import os
import sys
from cStringIO import StringIO
from datetime import datetime

import boto3
from jobs.base.base_etl import BaseETL
from jobs.wrappers.Zendesk.zendesk_api import ZendeskAPI


class ExtractZendeskDataToDatalake(object):
    def __init__(self, args):
        self.datalake_bucket_type = args[1]
        self.object_type = args[2]
        self.human_readable_start_time = datetime.strptime(args[3], '%Y-%m-%d %H:%M:%S').strftime('%Y-%m-%d')
        self.human_readable_end_time = datetime.strptime(args[4], '%Y-%m-%d %H:%M:%S').strftime('%Y-%m-%d')
        self.start_time = int(datetime.strptime(args[3], '%Y-%m-%d %H:%M:%S').strftime('%s'))
        self.end_time = int(datetime.strptime(args[4], '%Y-%m-%d %H:%M:%S').strftime('%s'))
        self.s3_datalake_bucket = args[5]
        self.s3_folder_path = args[6]
        self.s3 = boto3.client('s3')

        print ('m=init, datalake_bucket_type={}, object_type={}, start_time={}, human_readable_start_time={},'
               ' s3_datalake_bucket={}, s3_folder_path={}'.format(self.datalake_bucket_type, self.object_type,
                                                                  self.start_time, self.human_readable_start_time,
                                                                  self.s3_datalake_bucket, self.s3_folder_path))

        zendesk_login = json.loads(os.environ.get('ZENDESK_LOGIN'))
        self.zendesk_api = ZendeskAPI(
            subdomain=zendesk_login['host'],
            client_id=zendesk_login['client_id'],
            client_secret=zendesk_login['client_secret'],
            chat_client_id=zendesk_login['chat_client_id'],
            chat_client_secret=zendesk_login['chat_client_secret'],
            chat_token=zendesk_login['chat_token'],
            start_time=self.start_time,
            end_time=self.end_time
        )

    def load_data_from_zendesk_to_raw(self):
        partition = 'dt_timestamp={}'.format(datetime.now().strftime('%Y-%m-%d'))
        result = self.zendesk_api.get_data()
        print ('result_type: {}'.format(type(result)))

        count = 0
        handle = None
        with BaseETL.open_gzip_fp('wb') as fp:
            for item in result:
                BaseETL.write_json_in_fp(json.dumps(item.to_dict()), fp)
                count += 1
            handle = fp.fileobj
        self.save_data_to_s3(handle=handle, partition=partition, extension_file='gz')

        print ('final count: {}'.format(len(result)))

    def save_data_to_s3(self, data=None, handle=None, partition=None, extension_file='json'):
        if not data and not handle:
            raise Exception
        if not handle:
            handle = StringIO(str(json.dumps(data)).encode('utf-8'))

        target_file = '{}-{}.{}'.format(self.object_type, self.start_time, extension_file)
        if partition:
            target_file = '{}/{}'.format(partition, target_file)

        print (
            'm=save_data_to_s3, bucket_folder_path={0}, target_file={1}'.format(
                self.s3_datalake_bucket, target_file
            )
        )
        BaseETL.obj_to_s3(
            obj_io=handle,
            bucket=self.s3_datalake_bucket,
            file_path='{0}/{1}/{2}'.format(self.s3_folder_path, self.object_type, target_file)
        )

    def load_data_from_zendesk_to_clean(self):
        print('Not implemented yet...')


if __name__ == '__main__':
    args = sys.argv
    print ('START')
    zendesk_data_to_s3 = ExtractZendeskDataToDatalake(args)

    if zendesk_data_to_s3.datalake_bucket_type == 'raw':
        zendesk_data_to_s3.load_data_from_zendesk_to_raw()
    if zendesk_data_to_s3.datalake_bucket_type == 'clean':
        zendesk_data_to_s3.load_data_from_zendesk_to_clean()

    print ('END')
    sys.stdout.flush()
