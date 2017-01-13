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

    def __append(self, message, table=None):
        if not table:
            table = list()
            table.append(['dt_creation', 'message'])
        table.append([self.now(), message])
        return table

    def run_sqs_to_ods(self, sqs_queue_name, db_enum, table_name, batch_size=5000):
        sqs = boto3.resource('sqs')
        queue = sqs.get_queue_by_name(QueueName=sqs_queue_name)
        messages_to_delete = []
        end_of_messages = False
        table_insert = None
        print ('Total ApproximateNumberOfMessages: {}'.format(queue.attributes['ApproximateNumberOfMessages']))
        bn=0
        while not end_of_messages:
            bn +=1
            step = 'Start - batch number: {}'.format(bn)
            print(step)
            try:
                msgs = queue.receive_messages(MaxNumberOfMessages=10)
                if not msgs:
                    end_of_messages = True
                    if table_insert and messages_to_delete:
                        self._insert_messages(db_enum, table_insert, table_name)
                        self._delete_messages(messages_to_delete)
                else:
                    for message in msgs:
                        try:
                            m = self.get_message_content(message)
                            step = 'Get message content ok!'
                            table_insert = self.__append(m, table_insert) # db_enum, table_name, conn)
                            messages_to_delete.append(message)
                            step = 'Append table to insert'
                            print (step + ': {}'.format(batch_size))
                            if len(table_insert) > batch_size:
                                table_insert = self._insert_messages(db_enum, table_insert, table_name)
                                messages_to_delete = self._delete_messages(messages_to_delete)
                        except Exception as e:
                            if message:
                                print ('{0}\n{1} - STEP: {2}'.format(message.body, e, step))

            except Exception as e:
                print ('{} - STEP: {}'.format(e, step))

    def _insert_messages(self, db_enum, table_insert, table_name):
        count = len(table_insert)
        print('BULK INSERT - {} messages...'.format(count))
        self.bulk_insert(table=table_insert, table_name=table_name, db_enum=db_enum,
                         delimiter='|', encoding='LATIN-1')
        table_insert = None
        return table_insert

    def _delete_messages(self, messages_to_delete):
        count = len(messages_to_delete)
        print('Deleting {} messages...'.format(count))
        while count > 0:
            mes = messages_to_delete[0]
            mes.delete()
            messages_to_delete.remove(mes)
        return messages_to_delete

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
        sqs_queue_name = args[2] if arg_count > 2 else None
        batch_size = args[3] if arg_count > 3 else 10000
        a.run_sqs_to_ods(
            sqs_queue_name=sqs_queue_name,
            db_enum=EnumDb.BI_ODS,
            table_name='amplitude_event',
            batch_size=batch_size
        )

    print('END')
    # sys.stdout.flush()
