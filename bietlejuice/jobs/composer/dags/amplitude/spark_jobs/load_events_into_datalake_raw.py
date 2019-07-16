from datetime import datetime, timedelta
import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents
from bietlejuice.jobs.composer.base import BaseDBUtils

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger('load_events_into_datalake_raw')

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()

parser = ArgumentParser(description='Load amplitude events into datalake raw')
parser.add_argument('execution_date')
parser.add_argument('env')


def get_s3_raw_path(env):
    if env == 'forno':
        return 's3://5a-datalake-forno/raw_spark/amplitude/'
    elif env == 'prod':
        return 's3://5a-datalake/raw_spark/amplitude/'
    raise ValueError('The environment do not exists: {}'.format(env))


if __name__ == '__main__':
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env

    start_date = datetime.strptime(execution_date, '%Y-%m-%d')
    end_date = start_date + timedelta(hours=23)
    secrets_scope = 'quintoandar-{}'.format(env)
    keys = json.loads(dbutils.secrets.get(secrets_scope, 'ENV_AMPLITUDE'))
    db_raw = 'datalake_raw_spark'
    s3_raw_path = get_s3_raw_path(env)

    amplitude_events = AmplitudeEvents(db_raw, s3_raw_path, keys)
    amplitude_events.load_events_into_datalake_raw(start_date=start_date, end_date=end_date)
