import io
import logging
import zipfile

import boto3
from datetime import datetime, timedelta

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.wrappers.amplitude import amplitude_props_reader as props
from bietlejuice.jobs.wrappers.amplitude.amplitude_export_api import AmplitudeExportApi
from qa_python_utils.default_logger import _logger, logger

logging.getLogger('boto3').setLevel(logging.CRITICAL)

DEFAULT_DATETIME_FORMAT = '%Y-%m-%d %H:%M:%S'
AMPLITUDE_API_DATE_FORMAT = '%Y%m%dT%H'
LOCAL_TZ = 'America/Sao_Paulo'


class AmplitudeEventsETL(BaseETL):
    @logger
    def __init__(self, *args, **kwargs):
        super(AmplitudeEventsETL, self).__init__(*args, **kwargs)
        self.s3 = boto3.resource('s3')

    def dump_events_to_s3(self, f, app, start, hour):
        if isinstance(start, str):
            start = datetime.strptime(start, DEFAULT_DATETIME_FORMAT)
        if isinstance(start, datetime):
            start = start.date()

        date_partition = 'dt={}'.format(str(start))
        file_name = 'raw/amplitude/events/{}/{}_{}_{}.json.gz'.format(date_partition, app, str(start), hour)
        _logger.info('m=dump_events_to_s3, pushing file to s3 bucket={} filename={}'.format('5a-datalake', file_name))
        self.s3.Bucket('5a-datalake').put_object(Body=f.getvalue(), Key=file_name)

    @logger
    def extract_from_api_to_s3(self, start_date=None, end_date=None):
        start = start_date.strftime(AMPLITUDE_API_DATE_FORMAT)
        end = end_date.strftime(AMPLITUDE_API_DATE_FORMAT)

        if start and end:
            _logger.info('m=extract_from_api_to_s3, Param Start String: start={} end={}'.format(start, end))
            keys = props.get_keys()
            for key in keys:
                _logger.info('m=extract_from_api_to_s3, processing {}'.format(key['app']))
                a = AmplitudeExportApi(key['app_key'], key['secret_key'])
                _logger.info('dt={} m=extract_from_api_to_s3, get_files_from_extract_api'.format(datetime.now()))
                f = a.get_files_from_extract_api(start, end)
                if f:
                    with zipfile.ZipFile(f, 'r') as zfile:
                        for name in zfile.namelist():
                            hourly_gz = io.BytesIO(zfile.read(name))
                            hour = name.split('#')[0].split('_')[-1] # extract the hour from the file name
                            self.dump_events_to_s3(hourly_gz, key['app'], start_date, hour)
                            _logger.info('dt={} m=extract_from_api_to_s3, object sent name={} app={} hour={}'.format(
                                datetime.now(), name, key['app'], hour))


def convert_date(date_str):
    return datetime.strptime(date_str, DEFAULT_DATETIME_FORMAT)


# if __name__ == '__main__':
#     _logger.info('m=main debug, started program')
#     start_date = datetime(2017, 10, 1)
#     end_date = (start_date + timedelta(hours=23))
#
#     a = AmplitudeEventsETL()
#     a.extract_from_api_to_s3(start_date=start_date, end_date=end_date)
