import os
import sys
import json
import boto3
import pytz
from pytz import timezone
from datetime import datetime
from jobs.wrappers.amplitude.amplitude_export_api import AmplitudeExportApi, log, EnumDb
from jobs.wrappers.amplitude import amplitude_props_reader as props
from jobs.base.base_etl import BaseETL, log, EnumDb

DEFAULT_DATETIME_FORMAT = '%Y-%m-%d %H:%M:%S'
AMPLITUDE_API_DATE_FORMAT = '%Y%m%dT%H'
LOCAL_TZ = 'America/Sao_Paulo'

class AmplitudeEventsETL(BaseETL):

    def __init__(self, *args, **kwargs):
        super(AmplitudeEventsETL, self).__init__(*args, **kwargs)

    def __insert_db(self, message, db_enum, table_name):
        table = list()
        table.append(['dt_creation', 'message'])
        table.append([self.now(), json.dumps(message)])
        self.insert_data(db_enum=db_enum, data_table=table, table_name=table_name)

    def run_sqs_to_ods(self, sqs_queue_name, db_enum, table_name):
        sqs = boto3.resource('sqs')
        queue = sqs.get_queue_by_name(QueueName=sqs_queue_name)
        messages = []
        message = None
        end_of_messages = False
        while not end_of_messages:
            try:
                msgs = queue.receive_messages(MaxNumberOfMessages=10)
                if not msgs:
                    end_of_messages = True
                else:
                    for message in msgs:
                        m = self.get_message_content(message)
                        messages.append(m)
                        self.__insert_db(m, db_enum, table_name)
                        message.delete()
            except Exception as e:
                r = None
                if message:
                    r = message.body
                print ('{0}\n{1}'.format(r, e))
                # logError(message.body, e)
                pass
        return messages

    def run_source_to_sns(self, topic_arn, start_date=None, end_date=None, td=None, **kwargs):
        if not topic_arn:
            raise Exception("Param: topic_arn can't be None!")

        d = os.path.dirname(os.path.realpath(__file__))
        print('CurDir: ' + d)
        print('Kwargs: ' + unicode(kwargs))
        print('Start Date: {}'.format(start_date))
        print('End Date: {}'.format(end_date))
        sys.stdout.flush()

        start, end = self.check_dates(start_date, end_date, td, kwargs)

        if start and end:
            log('Param Start String: {}'.format(start))
            log('Param End String: {}'.format(end))

            for key in props.get_keys():
                a = AmplitudeExportApi(key['app_key'],key['secret_key'])
                f = a.get_files_from_extract_api(start, end)
                if f:
                    events = a.get_json_from_zipfile(f)
                    a.publish_notifications(events, topic_arn=topic_arn)
                    print('{} messages were published in SNS!'.format(len(events)))
                    sys.stdout.flush()

    @classmethod
    def check_dates(cls, start_date, end_date, td, kwargs):
        if kwargs and kwargs['execution_date'] and (not start_date or not end_date):
            # End equals Start beacuse Amplitude API works with Hour level, including all Minutes
            # So, start = 20160907T07 and end = 20160907T07, retrieves events from 20160907 07:00:00 to 07:59.59.99999
            end_date = kwargs['execution_date']
            start_date = end_date - td if td else end_date
        elif (start_date or end_date) and (isinstance(start_date, basestring) or isinstance(end_date, basestring)):
            start_date = datetime.strptime(start_date, DEFAULT_DATETIME_FORMAT)
            end_date = datetime.strptime(end_date, DEFAULT_DATETIME_FORMAT) if end_date else start_date

        if not start_date or not end_date:
            raise Exception("Dates can't be None!")

        return start_date.strftime(AMPLITUDE_API_DATE_FORMAT), end_date.strftime(AMPLITUDE_API_DATE_FORMAT)


def convert_date(date_str):
    dt = datetime.strptime(date_str, DEFAULT_DATETIME_FORMAT)
    return dt.replace(tzinfo=pytz.utc).astimezone(timezone(LOCAL_TZ))



if __name__ == '__main__':
    now = convert_date(datetime.utcnow().strftime(DEFAULT_DATETIME_FORMAT))
    args = sys.argv
    arg_count = len(args)

    print('START')
    a = AmplitudeEventsETL()
    if args[1] == 'source_to_sns':
        topic_arn = args[2] if arg_count > 2 else None
        start_date = convert_date(args[3]) if arg_count > 3 else now
        print start_date
        end_date = convert_date(args[4]) if arg_count > 4 else now
        print end_date
        td = args[5] if arg_count > 5 else None

        a.run_source_to_sns(topic_arn=topic_arn, start_date=start_date, end_date=end_date, td=td)

    elif args[1] == 'sqs_to_ods':
        sqs_queue_name = args[2] if arg_count > 1 else None
        messages = a.run_sqs_to_ods(sqs_queue_name=sqs_queue_name, db_enum=EnumDb.BI_ODS, table_name='amplitude_event')

    print('END')
    sys.stdout.flush()
