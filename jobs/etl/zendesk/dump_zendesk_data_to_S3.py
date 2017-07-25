import json
import os
import sys
from cStringIO import StringIO
from datetime import datetime
import io
import gzip

import boto3
from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from jobs.wrappers.Zendesk.zendesk_api import ZendeskAPI


class ZendeskDataToS3(object):
    def __init__(self, args):
        self.datalake_bucket_type = args[1]
        self.object_type = args[2]
        self.start_time = int(datetime.strptime(args[3], '%Y-%m-%d %H:%M:%S').strftime('%s'))
        self.human_readable_start_time = args[3]
        self.s3_datalake_bucket = args[4]
        self.s3_folder_path = args[5]
        self.s3 = boto3.client('s3')

        print ('m=init, datalake_bucket_type={}, object_type={}, start_time={}, human_readable_start_time={},'
               ' s3_datalake_bucket={}, s3_folder_path={}'.format(self.datalake_bucket_type, self.object_type,
                                                                  self.start_time, self.human_readable_start_time,
                                                                  self.s3_datalake_bucket, self.s3_folder_path))

        zendesk_login = json.loads(os.environ.get('ZENDESK_LOGIN'))
        self.zendesk_api = ZendeskAPI(subdomain=zendesk_login['host'], email=zendesk_login['email'],
                                      password=zendesk_login['password'], start_time=self.start_time)

    def load_data_from_zendesk_to_raw(self):
        partition = 'dt_timestamp={}'.format(datetime.now().strftime('%Y-%m-%d'))
        if self.object_type == 'ticket':
            result = self.zendesk_api.get_tickets_data()
        elif self.object_type == 'user':
            result = self.zendesk_api.get_users_data()
        elif self.object_type == 'ticket_metrics':
            result = self.zendesk_api.get_ticket_metrics_data()
        elif self.object_type == 'group':
            result = self.zendesk_api.get_groups_data()
        elif self.object_type == 'group_membership':
            result = self.zendesk_api.get_group_memberships_data()
        elif self.object_type == 'ticket_fields_type':
            result = self.zendesk_api.get_ticket_fields_type_data()
        elif self.object_type == 'chat':
            result = self.zendesk_api.zenpy_client.chats()
        else:
            return
        print ('result_type: {}'.format(type(result)))

        count = 0
        handle = None
        with BaseETL.open_gzip_fp('wb') as fp:
            for item in result:
                BaseETL.write_json_in_fp(json.dumps(item.to_dict()), fp)
                count += 1
            handle = fp.fileobj
        self.save_data_to_s3(handle=handle, partition=partition, extension_file='gz')

        print ('final count: {}'.format(count))

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
    zendesk_data_to_s3 = ZendeskDataToS3(args)

    if zendesk_data_to_s3.datalake_bucket_type == 'raw':
        zendesk_data_to_s3.load_data_from_zendesk_to_raw()
    if zendesk_data_to_s3.datalake_bucket_type == 'clean':
        zendesk_data_to_s3.load_data_from_zendesk_to_clean()

    print ('END')
    sys.stdout.flush()
