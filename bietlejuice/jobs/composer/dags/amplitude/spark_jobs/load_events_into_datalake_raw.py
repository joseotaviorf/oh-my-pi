from datetime import datetime, timedelta
import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents
from bietlejuice.jobs.composer.wrappers import AmplitudeExportApi
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
    start = start_date.strftime(AmplitudeEvents.AMPLITUDE_API_DATE_FORMAT)
    end = end_date.strftime(AmplitudeEvents.AMPLITUDE_API_DATE_FORMAT)

    keys = json.loads(dbutils.secrets.get("quintoandar", "ENV_AMPLITUDE"))

    db_info = AmplitudeDatabaseInfo.get_db_info(env)
    spark.sql("CREATE DATABASE IF NOT EXISTS {}".format(db_info["db_raw_databricks"]))
    amplitude_events = AmplitudeEvents(
        db_raw=db_info["db_raw_databricks"], s3_raw_path=db_info["db_raw_path"]
    )

    logger.info(
        "m=load_events_into_datalake_raw, Param Start String: start={} end={}".format(
            start, end
        )
    )
    for key in keys:
        logger.info(
            "m=load_events_into_datalake_raw, App id: {}, App name: {}".format(
                key["app_id"], key["app_name"]
            )
        )
        amplitude_export_api = AmplitudeExportApi(key["app_key"], key["secret_key"])
        logger.info("m=load_events_into_datalake_raw, get_files_from_extract_api")
        file_from_api = amplitude_export_api.get_files_from_extract_api(start, end)
        amplitude_events.load_events_into_datalake_raw(file_from_api)
