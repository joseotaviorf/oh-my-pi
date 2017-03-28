import json
import os
import sys
from cStringIO import StringIO

import boto3
from jobs.wrappers.Zendesk.zendesk_api import ZendeskAPI


class ZendeskDataToS3(object):
    def __init__(self, args):
        self.object_type = args[1]
        self.execution_date = args[2]
        self.s3_bucket = args[3]
        self.s3 = boto3.client('s3')

        zendesk_login = json.loads(os.environ.get('ZENDESK_LOGIN'))
        self.zendesk_api = ZendeskAPI(subdomain=zendesk_login['host'], email=zendesk_login['email'],
                                      password=zendesk_login['password'], start_time=self.execution_date)

    def load_data_from_zendesk(self):
        result = None
        if self.object_type == 'tickets':
            result = self.zendesk_api.get_tickets_data()
        if self.object_type == 'users':
            result = self.zendesk_api.get_users_data()

        if not result:
            return

        count = 0
        payload = []
        for r in result:
            payload.append(r.to_dict())
            count += 1
            if (count % 1000) == 0:
                self.save_data_to_s3(payload, count)
                payload = []

        # save remaining data
        self.save_data_to_s3(payload, count)

    def save_data_to_s3(self, data, count):
        target_file = '{}_{}-{}.json'.format(self.execution_date, self.object_type, count)
        fake_handle = StringIO(str(data).encode('utf-8'))

        self.s3.put_object(Bucket=self.s3_bucket, Key=target_file, Body=fake_handle.read())


if __name__ == '__main__':
    args = sys.argv
    print('START')
    zendesk_data_to_s3 = ZendeskDataToS3(args)
    zendesk_data_to_s3.load_data_from_zendesk()
    print ('END')
    sys.stdout.flush()
