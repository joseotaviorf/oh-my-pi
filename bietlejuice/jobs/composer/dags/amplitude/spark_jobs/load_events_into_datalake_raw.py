import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.airflow.environment import Environment
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents

JOB_NAME = "load_events_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_s3_raw_path(environment):
    if not Environment.is_valid_environment(environment):
        raise RuntimeError(
            "msg=environment %s invalid. Environments allowed are: "
            % ", ".join(Environment.get_valid_environments())
        )
    return "s3://5a-datalake-{}/raw/amplitude/".format(environment)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("execution_date")
    parser.add_argument("env")
    args = parser.parse_args()
    execution_date = args.execution_date
    environment = args.env

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    start_date = datetime.strptime(execution_date, "%Y-%m-%d")
    end_date = start_date + timedelta(hours=23)
    keys = json.loads(dbutils.secrets.get("quintoandar", "ENV_AMPLITUDE"))
    db_raw = "datalake_amplitude_raw"
    s3_raw_path = get_s3_raw_path(environment)

    amplitude_events = AmplitudeEvents(
        db_raw=db_raw, s3_raw_path=s3_raw_path, keys=keys
    )
    amplitude_events.load_events_into_datalake_raw(
        start_date=start_date, end_date=end_date
    )
