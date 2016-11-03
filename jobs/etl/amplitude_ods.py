import os
import sys
import pytz
from pytz import timezone
from datetime import datetime
from jobs.wrappers.amplitude.amplitude_extract_api import AmplitudeExportApi, log, EnumDb
from jobs.wrappers.amplitude import amplitude_props_reader as props


DEFAULT_DATETIME_FORMAT = '%Y-%m-%d %H:%M:%S'
AMPLITUDE_API_DATE_FORMAT = '%Y%m%dT%H'
LOCAL_TZ = 'America/Sao_Paulo'


def execute(start_date=None, end_date=None, td=None, **kwargs):
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
            a = AmplitudeExportApi(key['app_key'],key['secret_key'])
            f = a.get_files_from_extract_api(start, end)
            if f:
                events = a.get_json_from_zipfile(f)
                for e in events:
                    ev, user_properties, event_properties, groups, data = a.convert_to_tables(event_dicts=events)
                    a.to_db(db_enum=EnumDb.BI_ODS, data_table=ev, table_name='events')
                    a.to_db(db_enum=EnumDb.BI_ODS, data_table=user_properties, table_name='user_properties')
                    a.to_db(db_enum=EnumDb.BI_ODS, data_table=event_properties, table_name='event_properties')
                    a.to_db(db_enum=EnumDb.BI_ODS, data_table=groups, table_name='groups')
                    a.to_db(db_enum=EnumDb.BI_ODS, data_table=data, table_name='data')
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


def convert_date(dt):
    return dt.replace(tzinfo=pytz.utc).astimezone(timezone(LOCAL_TZ))


if __name__ == '__main__':
    print('START')

    args = sys.argv
    arg_count = len(args)
    now = convert_date(datetime.utcnow())

    start_date = convert_date(datetime.strptime(args[1], DEFAULT_DATETIME_FORMAT)) if arg_count > 1 else now.strftime(DEFAULT_DATETIME_FORMAT)
    print start_date
    end_date = convert_date(datetime.strptime(args[2], DEFAULT_DATETIME_FORMAT)) if arg_count > 2 else now.strftime(DEFAULT_DATETIME_FORMAT)
    print end_date
    td = args[3] if arg_count > 3 else None

    execute(start_date=start_date, end_date=end_date, td=td)

    print('END')
    sys.stdout.flush()
