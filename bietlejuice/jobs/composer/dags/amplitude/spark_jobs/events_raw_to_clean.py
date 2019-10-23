from datetime import datetime
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents
from bietlejuice.jobs.composer.base.spark import (
    BaseSparkContext,
    SparkDataFrameService,
    SparkMetastoreService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.dags.amplitude.spark_jobs.db_info import (
    AmplitudeDatabaseInfo,
)
from bietlejuice.jobs.composer.wrappers import SparkSQLCLient
from bietlejuice.jobs.composer.consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import SparkDataframeIntoDatalakeLoader

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("events_raw_to_clean")

spark, sqlContext = BaseSparkContext.spark, BaseSparkContext.sqlContext

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
    spark_sql_client = SparkSQLCLient(spark, sqlContext)
    metastore_service = SparkMetastoreService(
        db_info["db_clean_databricks"], db_info["db_clean_path"], spark_sql_client
    )
    dataframe_loader = SparkDataframeIntoDatalakeLoader(
        SparkTableStorageFormat.DEFAULT_CLEAN, metastore_service
    )
    dataframe_service = SparkDataFrameService()

    table_name = "events"
    partition_by_list = ["year", "month", "day", "event_type"]
    spark_sql_consumer = DatabricksConsumer({"db": db_info["db_raw_databricks"]})
    df = amplitude_events.create_clean_events_df(
        date, spark_sql_consumer, dataframe_service
    )
    dataframe_loader.overwrite_partition(
        df, partition_by_list, table_name, schema_merging=False
    )
    metastore_service.create_new_partitions_from_df(
        table_name, df, partition_by_list, parallelism=8
    )

    event_types = [
        "listing_page_viewed",
        "schedule_page_viewed",
        "landing_page_viewed",
        "lead_form_submitted",
        "visit_schedule_confirmed",
        #         "visit_intent_clicked",
        "login_confirmation_viewed",
        "home_page_viewed",
        "signup_user_created",
    ]
    for event_type in event_types:
        table_name = "{}_events".format(event_type)
        partition_by_list = ["year", "month", "day"]
        spark_sql_consumer = DatabricksConsumer({"db": db_info["db_clean_databricks"]})
        df = amplitude_events.create_filtered_clean_events_df(
            date, event_type, spark_sql_consumer, dataframe_service
        )
        dataframe_loader.overwrite_partition(
            df, partition_by_list, table_name, schema_merging=True
        )
        metastore_service.create_new_partitions_from_df(
            table_name, df, partition_by_list, parallelism=8
        )
