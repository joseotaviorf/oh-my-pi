import json
import os
import sys
from cStringIO import StringIO
from datetime import datetime

import boto3
from jobs.wrappers.Zendesk.zendesk_api import ZendeskAPI


class ZendeskDataToS3(object):
    def __init__(self, args):
        self.object_type = args[1]
        self.start_time = int(datetime.strptime(args[2], '%Y-%m-%d %H:%M:%S').strftime('%s'))
        self.s3_bucket = args[3]
        self.s3 = boto3.client('s3')

        zendesk_login = json.loads(os.environ.get('ZENDESK_LOGIN'))
        self.zendesk_api = ZendeskAPI(subdomain=zendesk_login['host'], email=zendesk_login['email'],
                                      password=zendesk_login['password'], start_time=self.start_time)

    def load_data_from_zendesk(self):
        result = None
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

        if not result:
            return

        count = 0
        for _ in result:
            count += 1
            if (count % 1000) == 0:
                self.save_data_to_s3(result._json, count)

        # save remaining data
        self.save_data_to_s3(result._json, count)

        print 'final count: {}'.format(count)

    def save_data_to_s3(self, data, count):
        target_file = '{}_{}-{}.json'.format(self.start_time, self.object_type, count)
        print 'm=save_data_to_s3, target_file={}'.format(target_file)

        fake_handle = StringIO(str(json.dumps(data)).encode('utf-8'))
        self.s3.put_object(Bucket=self.s3_bucket, Key='{}/{}'.format(self.object_type, target_file),
                           Body=fake_handle.read())


if __name__ == '__main__':
    args = sys.argv
    print 'START'
    zendesk_data_to_s3 = ZendeskDataToS3(args)
    zendesk_data_to_s3.load_data_from_zendesk()
    print 'END'
    sys.stdout.flush()
