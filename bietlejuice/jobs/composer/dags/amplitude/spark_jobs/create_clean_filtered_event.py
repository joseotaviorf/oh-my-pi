import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseSparkContext,
    SparkDataFrameService,
    SparkMetastoreService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.wrappers import SparkSQLCLient

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("events_raw_to_clean")

spark, sqlContext = BaseSparkContext.spark, BaseSparkContext.sqlContext

parser = ArgumentParser(description="events_raw_to_clean")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("event_type")

if __name__ == "__main__":
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    event_type = args.event_type

    # setup
    date = datetime.strptime(execution_date, "%Y-%m-%d")
    source = "amplitude"
    db_info = DatalakeMetastoreService.get_db_info(env, source)

    amplitude_events = AmplitudeEvents(
        spark_client=SparkClient(),
        db_raw=db_info["db_raw_databricks"],
        db_clean=db_info["db_clean_databricks"],
    )
    metastore_service = SparkMetastoreService(
        db_info["db_clean_databricks"],
        db_info["db_clean_path"],
        SparkSQLCLient(spark, sqlContext),
    )
    s3_loader = S3Loader(metastore_service)
    dataframe_service = SparkDataFrameService()

    # create filtered events table
    table_name = "{}_events".format(event_type)
    partitions = ["year", "month", "day"]
    spark_sql_consumer = DatabricksConsumer(
        {"db": db_info["db_clean_databricks"]}, SparkClient()
    )
    df = amplitude_events.create_filtered_clean_events_df(
        date, event_type, spark_sql_consumer, dataframe_service
    )
    s3_loader.load_incremental_table(
        df,
        table_name,
        SparkTableStorageFormat.DEFAULT_CLEAN,
        partitions,
        schema_merging=True,
    )
    metastore_service.create_new_partitions_from_df(
        table_name, df, partitions, parallelism=1
    )
