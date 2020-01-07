import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.services import SparkDataFrameService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_clean_filtered_event")

parser = ArgumentParser(description="create_clean_filtered_event")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("event_type")

if __name__ == "__main__":
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    event_type = args.event_type

    # setup
    source = "amplitude"
    date = datetime.strptime(execution_date, "%Y-%m-%d")
    db_info = DatalakeMetastoreService.get_db_info(env, source)
    spark_client = SparkClient()
    amplitude_events = AmplitudeEvents(
        spark_client=spark_client,
        db_raw=db_info["db_raw_databricks"],
        db_clean=db_info["db_clean_databricks"],
    )
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader(metastore_service)
    dataframe_service = SparkDataFrameService()

    # create filtered events table
    database_name = db_info["db_clean_databricks"]
    table_name = "{}_events".format(event_type)
    partition_cols = ["year", "month", "day"]
    spark_sql_consumer = DatabricksConsumer(
        {"db": db_info["db_clean_databricks"]}, spark_client
    )
    df = amplitude_events.create_filtered_clean_events_df(
        date, event_type, spark_sql_consumer, dataframe_service
    )
    s3_loader.load_incremental_table(
        df=df,
        database_name=db_info["db_clean_databricks"],
        table_name=table_name,
        format_options=SparkTableStorageFormat.DEFAULT_CLEAN,
        database_location=db_info["db_clean_path"],
        partition_cols=partition_cols,
        schema_merging=True,
    )
    metastore_service.create_new_partitions_from_df(
        database_name, table_name, df, partition_cols
    )
    metastore_service.refresh_table(database_name, table_name)
