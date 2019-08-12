from datetime import datetime, timedelta
import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.base.spark import BaseSparkContext
from bietlejuice.jobs.composer.dags.amplitude.spark_jobs.db_info import (
    AmplitudeDatabaseInfo,
)

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("load_events_into_datalake_raw")

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()

spark = BaseSparkContext.spark

parser = ArgumentParser(description="load_events_into_datalake_raw")
parser.add_argument("execution_date")
parser.add_argument("env")

if __name__ == "__main__":
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env

    start_date = datetime.strptime(execution_date, "%Y-%m-%d")
    end_date = start_date + timedelta(hours=23)
    secrets_scope = "quintoandar-{}".format(env)
    keys = json.loads(dbutils.secrets.get(secrets_scope, "ENV_AMPLITUDE"))

    db_info = AmplitudeDatabaseInfo.get_db_info(env)
    db_raw_databricks = db_info["db_raw_databricks"]
    db_raw_path = db_info["db_raw_path"]

    amplitude_events = AmplitudeEvents(
        db_raw=db_raw_databricks, s3_raw_path=db_raw_path, keys=keys
    )

    spark.sql("CREATE DATABASE IF NOT EXISTS {}".format(db_raw_databricks))
    amplitude_events.load_events_into_datalake_raw(
        start_date=start_date, end_date=end_date
    )
