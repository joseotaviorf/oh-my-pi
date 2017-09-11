import os
import io
import sys
import boto3
import json
import gzip
import pytz
from datetime import datetime, timedelta
from jobs.wrappers.amplitude.amplitude_export_api import AmplitudeExportApi
from jobs.wrappers.amplitude import amplitude_props_reader as props
from jobs.base.base_etl import BaseETL, log, EnumDb
from qa_python_utils.aws.athena import AthenaClient

DEFAULT_DATETIME_FORMAT = '%Y-%m-%d %H:%M:%S'
AMPLITUDE_API_DATE_FORMAT = '%Y%m%dT%H'
LOCAL_TZ = 'America/Sao_Paulo'


class AmplitudeEventsETL(BaseETL):

    def __init__(self, *args, **kwargs):
        super(AmplitudeEventsETL, self).__init__(*args, **kwargs)
        self.s3 = boto3.resource('s3')
        self.BUCKET = "5a-amplitude-events"

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
        bn = 0
        while not end_of_messages:
            bn += 1
            step = 'Start - batch number: {}'.format(bn)
            print(step)
            msgs = queue.receive_messages(MaxNumberOfMessages=10)
            if not msgs:
                end_of_messages = True
                if table_insert and messages_to_delete:
                    self._insert_messages(db_enum, table_insert, table_name)
                    self._delete_messages(messages_to_delete)
            else:
                for message in msgs:
                    m = self.get_message_content(message)
                    table_insert = self.__append(m, table_insert) # db_enum, table_name, conn)
                    messages_to_delete.append(message)
                    if len(table_insert) > batch_size:
                        self._insert_messages(db_enum, table_insert, table_name)
                        messages_to_delete = self._delete_messages(messages_to_delete)
                        table_insert = None

    def _insert_messages(self, db_enum, table_insert, table_name):
        table_name_raw = table_name + '_raw'
        count = len(table_insert)
        print('BULK INSERT - {} messages...'.format(count))

        self.bulk_insert(table=table_insert, table_name=table_name_raw, db_enum=db_enum, append=True,
                         delimiter='|', encoding='LATIN-1')

        self.execute_command(
            db_enum=EnumDb.BI_ODS,
            command='INSERT INTO {0}(dt_creation, message) SELECT dt_creation, message FROM {1}'.format(
                table_name, table_name_raw
            ),
            commit=True
        )

        self.execute_command(
            db_enum=EnumDb.BI_ODS,
            command='TRUNCATE TABLE {0}'.format(table_name_raw),
            commit=True
        )

    @classmethod
    def _delete_messages(cls, messages_to_delete):
        print('Deleting {} messages...'.format(len(messages_to_delete)))
        while messages_to_delete:
            mes = messages_to_delete[0]
            mes.delete()
            messages_to_delete.remove(mes)
        return messages_to_delete

    @staticmethod
    def group_events(ev):
        events = {}
        for e in ev:
            if json.loads(e)['event_type'] not in events:
                events[json.loads(e)['event_type']] = ""
            events[json.loads(e)['event_type']] += e
            events[json.loads(e)['event_type']] += "\n"
        return events, str(json.loads(e)['app'])

    def dump_events_to_s3(self, g_events, app, start):
        if type(start) is str:
            start = datetime.strptime(start, DEFAULT_DATETIME_FORMAT)

        # old job
        app_partition = "app=" + app
        date_partition = "server_upload_date=" + str(start.date())

        for k, v in g_events.iteritems():
            event_partition = "event_type=" + k
            file_name = "/".join([app_partition, event_partition, date_partition, str(start.hour)]) + ".json.gz"
            gz_body = io.BytesIO()
            with gzip.GzipFile(fileobj=gz_body, mode="w") as fp:
                fp.write(v.encode('utf-8'))
            self.s3.Bucket(self.BUCKET).put_object(Body=gz_body.getvalue(), Key=file_name)

        # new job
        date_partition = 'dt={}'.format(str(start.date()))
        for k, v in g_events.iteritems():
            event_partition = 'et={}'.format(k)
            file_name = 'raw/amplitude/events/{}/{}/{}/{}_h{}.json.gz'.format(date_partition, event_partition,
                                                                              app_partition, str(start.date()),
                                                                              str(start.hour))
            gz_body = io.BytesIO()
            with gzip.GzipFile(fileobj=gz_body, mode='w') as fp:
                fp.write(v.encode('utf-8'))

            self.s3.Bucket('5a-datalake').put_object(Body=gz_body.getvalue(), Key=file_name)

    def run_source_to_sns(self, topic_arn, start_date=None, end_date=None, td=timedelta(hours=1), **kwargs):
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
            keys = props.get_keys()
            for key in keys:
                a = AmplitudeExportApi(key['app_key'], key['secret_key'])
                f = a.get_files_from_extract_api(start, end)
                if f:
                    events = a.get_json_from_zipfile(f)
                    g_events, app = self.group_events(events)
                    self.dump_events_to_s3(g_events, app, start_date)
                    count = a.publish_notifications(events, topic_arn=topic_arn)
                    print('{} messages were published in SNS!'.format(count))
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
    return dt.replace(tzinfo=pytz.utc).astimezone(pytz.timezone(LOCAL_TZ))


if __name__ == '__main__':
    now = (datetime.utcnow() - timedelta(hours=2)).strftime(DEFAULT_DATETIME_FORMAT)
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
            table_name='amplitude.events',
            batch_size=batch_size
        )

    elif args[1] == 'load_schedule_visit':
        table_name='booked_visit'
        # BaseETL.drop_table(db_enum=EnumDb.BI_ODS, table_name=table_name)
        vw = BaseETL.from_db_table(
            db_enum=EnumDb.BI_ODS,
            table_name='amplitude.vw_{}'.format(table_name),
            server_cursor_postgres=table_name
        )
        BaseETL.bulk_insert(
            table=vw,
            table_name='amplitude.{}'.format(table_name),
            db_enum=EnumDb.BI_ODS,
            append=False,
            commit=True
        )

    print('END')
    sys.stdout.flush()
