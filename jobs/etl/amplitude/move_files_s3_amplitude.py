import os
import re

import boto3
from qa_python_utils.default_logger import _logger

s3 = boto3.resource('s3')
amplitude_old = s3.Bucket('5a-amplitude-events')

app_env = os.environ['app']

for obj in amplitude_old.objects.filter(Prefix='app={}'.format(app_env)):
    if '$folder$' not in str(obj) and '%22' not in str(obj) and '%5' not in str(obj):
        _logger.info('str_obj={}'.format(str(obj)))

        try:
            result = re.search('key=u\'(.*)/event_type=(.*)/server_upload_date=(.*)/(.*)\'', str(obj)).groups()

            app = result[0]
            et = result[1].encode('utf-8')

            dt = result[2]
            file_name = result[3]
            _logger.info('app={}'.format(app))
            _logger.info('event_type={}'.format(et))
            _logger.info('server_upload_date={}'.format(dt))
            _logger.info('file={}'.format(file_name))

            from_bucket = '{}/event_type={}/server_upload_date={}/{}'.format(app, et, dt, file_name)
            copy_source = {
                'Bucket': '5a-amplitude-events',
                'Key': from_bucket
            }

            to_bucket = 'raw/amplitude/events/dt={}/et={}/{}_h{}'.format(dt, et, dt, file_name)

            _logger.info('from_bucket={}'.format(from_bucket))
            _logger.info('to_bucket={}'.format(to_bucket))

            s3.meta.client.copy(copy_source, '5a-datalake', to_bucket)

        except Exception:
            print 'ERROR at obj={}'.format(str(obj))
