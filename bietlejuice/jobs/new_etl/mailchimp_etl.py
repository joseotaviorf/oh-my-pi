import gzip
import io
import json
import os
import sys
from datetime import datetime, timedelta

import boto3
from bietlejuice.jobs.base.base_etl import BaseETL, log, EnumDb
from bietlejuice.jobs.wrappers.amplitude import amplitude_props_reader as props
from bietlejuice.jobs.wrappers.amplitude.amplitude_export_api import AmplitudeExportApi
from bietlejuice.jobs.new_etl.mailchimp_export_api import MailchimpExportApi

DEFAULT_DATETIME_FORMAT = '%Y-%m-%d %H:%M:%S'
AMPLITUDE_API_DATE_FORMAT = '%Y%m%dT%H'
LOCAL_TZ = 'America/Sao_Paulo'


class MailchimpETL(BaseETL):

    def __init__(self, *args, **kwargs):
        super(MailchimpETL, self).__init__(*args, **kwargs)
        self.s3 = boto3.resource('s3')
        #self.BUCKET = "5a-amplitude-events"
        self.BUCKET = "5a-mailchimp"

    def run_source_to_sns(self, file_type, start_date, end_date):
        # if not topic_arn:
        #     raise Exception("Param: topic_arn can't be None!")

        d = os.path.dirname(os.path.realpath(__file__))
        print('CurDir: ' + d)

        mc = MailchimpExportApi()
        f = mc.get_files_from_extract_api(file_type, start_date, end_date)

        if f:
            #lines = mc.get_json_from_zipfile(f)
            g_lines = self.format_lines(f, file_type)
            #self.dump_events_to_s3(g_lines, datetime.now(), file_type)
            # count = a.publish_notifications(events, topic_arn=topic_arn)
            # print('{} messages were published in SNS!'.format(count))
            self.dump_json_to_s3(g_lines, start_date, file_type)

#     return dt.replace(tzinfo=pytz.utc).astimezone(pytz.timezone(LOCAL_TZ))

    def dump_json_to_s3(self, json_list, start, file_type):
        if isinstance(start, str):
            start = datetime.strptime(start, DEFAULT_DATETIME_FORMAT)

        date_partition = 'dt={}'.format(str(start.date()))
        file_name = 'raw/mailchimp/{}/{}/{}_h{}.json.gz'.format(file_type, date_partition, str(start.date()),
                                                                str(start.hour))
        gz_body = io.BytesIO()
        json_str = json.dumps(json_list)
        with gzip.GzipFile(fileobj=gz_body, mode='w') as fp:
            fp.write(json_str.encode('utf-8'))

        self.s3.Bucket('5a-datalake').put_object(Body=gz_body.getvalue(), Key=file_name)

    def format_lines(self, ev, file_type):
        lines = {}
        for e in ev:
            #if json.loads(e)['templates'] not in lines:
            lines = json.loads(e)['{}'.format(file_type)]
        return lines #, str(json.loads(e)['app'])


if __name__ == '__main__':

    print('START')
    mc = MailchimpETL()
    print('CREATED')
    mc.run_source_to_sns('templates', '2018-05-02T00:00:00+00:00', '2018-05-02T23:59:59+00:00')
    print('GENERATED')
