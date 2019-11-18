from datetime import datetime
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents
from bietlejuice.jobs.composer.base.spark import (
    BaseSparkContext,
    SparkDataFrameService,
    SparkMetastoreService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.wrappers import SparkSQLCLient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import SparkDataframeIntoDatalakeLoader

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
    partition_by = args.partition_by

    # setup
    date = datetime.strptime(execution_date, "%Y-%m-%d")
    source = "amplitude"
    db_info = DatalakeMetastoreService.get_db_info(env, source)

    amplitude_events = AmplitudeEvents(
        spark_client=SparkClient(),
        db_raw=db_info["db_raw_databricks"],
        db_clean=db_info["db_clean_databricks"],
    )
    spark_sql_client = SparkSQLCLient(spark, sqlContext)
    metastore_service = SparkMetastoreService(
        db_info["db_clean_databricks"], db_info["db_clean_path"], spark_sql_client
    )
    dataframe_loader = SparkDataframeIntoDatalakeLoader(
        SparkTableStorageFormat.DEFAULT_CLEAN, metastore_service
    )
    dataframe_service = SparkDataFrameService()
    spark_sql_consumer = DatabricksConsumer(
        {"db": db_info["db_raw_databricks"]}, SparkClient()
    )

    # create events_repartitioned in datalake
    df = amplitude_events.create_clean_events_df(
        date, spark_sql_consumer, dataframe_service, partition_by
    )
    dataframe_loader.overwrite_partition(
        df, partition_by, table_name, schema_merging=False
    )
    metastore_service.create_new_partitions_from_df(
        table_name, df, partition_by, parallelism=1
    )
