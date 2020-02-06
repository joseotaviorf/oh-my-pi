import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseSparkContext,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("events_repartitioned_raw_to_clean")

spark, sqlContext = BaseSparkContext.spark, BaseSparkContext.sqlContext

parser = ArgumentParser(description="events_repartitioned_raw_to_clean")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("table_name")
parser.add_argument("--partition_by", nargs="+", dest="partition_by", required=False)

if __name__ == "__main__":
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    table_name = args.table_name
    partition_cols = args.partition_by

    # setup
    date = datetime.strptime(execution_date, "%Y-%m-%d")
    source = "amplitude"
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
    spark_sql_consumer = DatabricksConsumer(
        {"db": db_info["db_raw_databricks"]}, spark_client
    )

    # create events_repartitioned in datalake
    df = amplitude_events.create_clean_events_df(
        date, spark_sql_consumer, dataframe_service, partition_cols
    )
    s3_loader.load_incremental_table(
        df=df,
        database_name=db_info["db_clean_databricks"],
        table_name=table_name,
        format_options=SparkTableStorageFormat.DEFAULT_CLEAN,
        database_location=db_info["db_clean_path"],
        partition_cols=partition_cols,
    )
    database_name = db_info["db_clean_databricks"]
    metastore_service.create_new_partitions_from_df(
        database_name, table_name, df, partition_cols
    )
    metastore_service.refresh_table(database_name, table_name)
