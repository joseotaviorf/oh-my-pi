from datetime import datetime, timedelta
import sys
import json
import logging

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEventsETL
from bietlejuice.jobs.composer.base import BaseDBUtils

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger('load_docx_into_datalake')

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()


@logger
def main():
    execution_date = sys.argv[1:][0]
    start_date = datetime.strptime(execution_date, '%Y-%m-%d')
    end_date = start_date + timedelta(hours=23)

    keys = json.loads(dbutils.secrets.get('quintoandar-forno', 'ENV_AMPLITUDE'))
    AmplitudeEventsETL.load_events_into_datalake_raw(start_date=start_date, end_date=end_date, keys=keys)


if __name__ == '__main__':
    main()
