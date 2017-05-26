import json
import os
import sys
from cStringIO import StringIO
from datetime import datetime

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
        self.s3_bucket = args[4]
        self.s3 = boto3.client('s3')

        zendesk_login = json.loads(os.environ.get('ZENDESK_LOGIN'))
        self.zendesk_api = ZendeskAPI(subdomain=zendesk_login['host'], email=zendesk_login['email'],
                                      password=zendesk_login['password'], start_time=self.start_time)

    def load_data_from_zendesk_to_raw(self):
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
        else:
            return

        count = 0
        for _ in result:
            count += 1
            if (count % 1000) == 0:
                self.save_data_to_s3(result._json, count)

        # save remaining data
        self.save_data_to_s3(result._json, count)

        print ('final count: {}'.format(count))

    def save_data_to_s3(self, data, count):
        target_file = '{}_{}-{}.json'.format(self.start_time, self.object_type, count)
        print ('m=save_data_to_s3, bucket_folder_path={0}, target_file={1}'.format(self.s3_bucket, target_file))

        fake_handle = StringIO(str(json.dumps(data)).encode('utf-8'))
        self.s3.put_object(Bucket=self.s3_bucket, Key='{0}/{1}/{2}'.format(self.datalake_bucket_type,
                                                                           self.object_type, target_file),
                           Body=fake_handle.read())

    def load_data_from_zendesk_to_clean(self):
        table = BaseETL.from_db_table(
            db_enum=EnumDb.BI_ODS,
            table_name='zendesk.{}'.format(self.object_type)
        )

        BaseETL.to_s3(
            filename=self.object_type + '.csv',
            data_table=table,
            bucket_name='{0}/{1}/{2}'.format(self.s3_bucket, self.datalake_bucket_type, self.object_type)
        )


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
