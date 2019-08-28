from datetime import datetime
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents
from bietlejuice.jobs.composer.base.spark import (
    BaseSparkContext,
    DataFrameService,
    MetastoreService,
    TableStorageFormat,
)
from bietlejuice.jobs.composer.dags.amplitude.spark_jobs.db_info import (
    AmplitudeDatabaseInfo,
)
from bietlejuice.jobs.composer.wrappers import SparkSQLCLient
from bietlejuice.jobs.composer.consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import DataframeIntoDatalakeLoader

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

    amplitude_events = AmplitudeEvents(
        db_raw=db_info["db_raw_databricks"], db_clean=db_info["db_clean_databricks"]
    )
    spark_sql_client = SparkSQLCLient(spark)
    metastore_service = MetastoreService(
        db_info["db_clean_databricks"], db_info["db_clean_path"], spark_sql_client
    )
    dataframe_loader = DataframeIntoDatalakeLoader(
        TableStorageFormat.DEFAULT_CLEAN, metastore_service
    )
    dataframe_service = DataFrameService()

    table_name = "events"
    spark_sql_consumer = DatabricksConsumer({"db": db_info["db_raw_databricks"]})
    df = amplitude_events.create_clean_events_df(
        date, spark_sql_consumer, dataframe_service
    )
    dataframe_loader.partition_overwrite_load(
        df, ["year", "month", "day", "event_type"], table_name, schema_merging=False
    )
    metastore_service.update_table_partitions(table_name)

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
        table_name = "{}_events".format(event_type)
        spark_sql_consumer = DatabricksConsumer({"db": db_info["db_clean_databricks"]})
        df = amplitude_events.create_filtered_clean_events_df(
            date, event_type, spark_sql_consumer, dataframe_service
        )
        dataframe_loader.partition_overwrite_load(
            df, ["year", "month", "day"], table_name, schema_merging=True
        )
        metastore_service.update_table_partitions(table_name)
