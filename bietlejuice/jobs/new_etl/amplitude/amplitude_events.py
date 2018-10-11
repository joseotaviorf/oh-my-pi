import io
import zipfile
from datetime import datetime

import boto3
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.wrappers.amplitude import amplitude_props_reader as props
from bietlejuice.jobs.wrappers.amplitude.amplitude_export_api import AmplitudeExportApi
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('AmplitudeEventsETL')

DEFAULT_DATETIME_FORMAT = '%Y-%m-%d %H:%M:%S'
AMPLITUDE_API_DATE_FORMAT = '%Y%m%dT%H'
LOCAL_TZ = 'America/Sao_Paulo'


class AmplitudeEventsETL(BaseETL):
    @logger
    def __init__(self, *args, **kwargs):
        super(AmplitudeEventsETL, self).__init__(*args, **kwargs)
        self.s3 = boto3.resource('s3')

    def dump_events_to_s3(self, f, app, start, hour, extra):
        if isinstance(start, str):
            start = datetime.strptime(start, DEFAULT_DATETIME_FORMAT)
        if isinstance(start, datetime):
            start = start.date()

        date_partition = 'dt={}'.format(str(start))
        file_name = 'raw/amplitude/events/{}/{}_{}_{}_{}.json.gz'.format(date_partition, app, str(start), hour, extra)
        logger.info('m=dump_events_to_s3, pushing file to s3 bucket={} filename={}'.format('5a-datalake', file_name))
        self.s3.Bucket('5a-datalake').put_object(Body=f.getvalue(), Key=file_name)

    @logger
    def extract_from_api_to_s3(self, start_date=None, end_date=None):
        start = start_date.strftime(AMPLITUDE_API_DATE_FORMAT)
        end = end_date.strftime(AMPLITUDE_API_DATE_FORMAT)

        if start and end:
            logger.info('m=extract_from_api_to_s3, Param Start String: start={} end={}'.format(start, end))
            keys = props.get_keys()
            for key in keys:
                logger.info('m=extract_from_api_to_s3, processing {}'.format(key['app']))
                a = AmplitudeExportApi(key['app_key'], key['secret_key'])
                logger.info('dt={} m=extract_from_api_to_s3, get_files_from_extract_api'.format(datetime.now()))
                f = a.get_files_from_extract_api(start, end)
                if f:
                    with zipfile.ZipFile(f, 'r') as zfile:
                        for name in zfile.namelist():
                            hourly_gz = io.BytesIO(zfile.read(name))
                            hour = name.split('#')[0].split('_')[-1]  # extract the hour from the file name
                            extra = name.split('#')[1].split('.')[0]  # putting the extra on the name for deduplication
                            self.dump_events_to_s3(hourly_gz, key['app'], start_date, hour, extra)
                            logger.info('dt={} m=extract_from_api_to_s3, object sent name={} app={} hour={} extra={}'.
                                        format(datetime.now(), name, key['app'], hour, extra))


def convert_date(date_str):
    return datetime.strptime(date_str, DEFAULT_DATETIME_FORMAT)
