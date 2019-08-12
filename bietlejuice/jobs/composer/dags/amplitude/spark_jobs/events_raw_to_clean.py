from datetime import datetime
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents
from bietlejuice.jobs.composer.base.spark import BaseSparkContext
from bietlejuice.jobs.composer.dags.amplitude.spark_jobs.db_info import (
    AmplitudeDatabaseInfo,
)

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("events_raw_to_clean")

spark = BaseSparkContext.spark

parser = ArgumentParser(description="events_raw_to_clean")
parser.add_argument("execution_date")
parser.add_argument("env")

if __name__ == "__main__":
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    db_info = AmplitudeDatabaseInfo.get_db_info(env)
    db_raw_databricks = db_info["db_raw_databricks"]
    db_raw_path = db_info["db_raw_path"]
    db_clean_databricks = db_info["db_clean_databricks"]
    db_clean_path = db_info["db_clean_path"]

    amplitude_events = AmplitudeEvents(
        db_raw=db_raw_databricks,
        s3_raw_path=db_raw_path,
        db_clean=db_clean_databricks,
        s3_clean_path=db_clean_path,
    )

    spark.sql("CREATE DATABASE IF NOT EXISTS {}".format(db_clean_databricks))
    amplitude_events.update_clean_amplitude_events(date=date)

    event_types = [
        "listing_page_viewed",
        "schedule_page_viewed",
        "landing_page_viewed",
        "lead_form_submitted",
        "visit_schedule_confirmed",
        "visit_intent_clicked",
        "login_confirmation_viewed",
        "home_page_viewed",
        "signup_user_created",
    ]
    for event_type in event_types:
        amplitude_events.update_filtered_events_table(date=date, event_type=event_type)
