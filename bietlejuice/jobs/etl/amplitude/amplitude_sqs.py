import os
import sys
from datetime import datetime

import pytz
from pytz import timezone

from bietlejuice.jobs.wrappers.amplitude import amplitude_props_reader as props
from bietlejuice.jobs.wrappers.amplitude.amplitude_export_api import AmplitudeExportApi, log

DEFAULT_DATETIME_FORMAT = '%Y-%m-%d %H:%M:%S'
AMPLITUDE_API_DATE_FORMAT = '%Y%m%dT%H'
LOCAL_TZ = 'America/Sao_Paulo'


def execute(queue_name, start_date=None, end_date=None, td=None, **kwargs):
    if not queue_name:
        raise Exception("Param: queue_name can't be None!")

    d = os.path.dirname(os.path.realpath(__file__))
    print('CurDir: ' + d)
    print('Kwargs: ' + unicode(kwargs))
    print('Start Date: {}'.format(start_date))
    print('End Date: {}'.format(end_date))
    sys.stdout.flush()

    start, end = check_dates(start_date, end_date, td, kwargs)

    if start and end:
        log('Param Start String: {}'.format(start))
        log('Param End String: {}'.format(end))

        for key in props.get_keys():
            a = AmplitudeExportApi(key['app_key'], key['secret_key'])
            f = a.get_files_from_extract_api(start, end)
            if f:
                events = a.get_json_from_zipfile(f)
                a.publish_messages(events, queue_name)
                print('{} messages published on SQS!'.format(len(list(events))))
                sys.stdout.flush()


def check_dates(start_date, end_date, td, kwargs):
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


def convert_date(date):
    dt = datetime.strptime(date, DEFAULT_DATETIME_FORMAT)
    return dt.replace(tzinfo=pytz.utc).astimezone(timezone(LOCAL_TZ))


if __name__ == '__main__':
    print('START')

    args = sys.argv
    print(args)
    arg_count = len(args)
    now = convert_date(datetime.utcnow().strftime(DEFAULT_DATETIME_FORMAT))

    queue_name = args[1] if arg_count > 1 else None
    start_date = convert_date(args[2]) if arg_count > 2 else now
    end_date = convert_date(args[3]) if arg_count > 3 else now
    td = args[4] if arg_count > 4 else None

    execute(queue_name=queue_name, start_date=start_date, end_date=end_date, td=td)

    print('END')
    sys.stdout.flush()
