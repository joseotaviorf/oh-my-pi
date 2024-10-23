import logging
from functools import reduce
from argparse import ArgumentParser
from datetime import datetime, timedelta

from pyspark.sql.functions import lit
from pyspark.sql import DataFrame


from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import spark
from bietlejuice.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
)

from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

from quintoandar_logger import QuintoAndarLogger

import boto3

JOB_NAME = "load_hmb_ada_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def create_dataframe(source_bucket: str, table: str, dt: datetime) -> DataFrame:
  file_path = f"{table}/{dt.year}/{dt.month:02}/{dt.day:02}"
  if checkPath(source_bucket, file_path):
    df = (
      spark
      .read
      .parquet(f"s3://{source_bucket}/{file_path}")
    )
    
    if len(df.head(1)) == 0:
      logger.warning(f"m=__main__, msg=Empty dataframe for {table}.")
      return None
    
    return (
      df
      .withColumn("year", lit(dt.year))
      .withColumn("month", lit(dt.month))
      .withColumn("day", lit(dt.day))
    )

def checkPath(source_bucket: str, file_path: str) -> DataFrame:
  result = client.list_objects(Bucket=source_bucket, Prefix=file_path)
  exists=False
  if 'Contents' in result:
      exists=True
  return exists

client = boto3.client('s3')
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("raw_table_name")

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    start_date = datetime.strptime(args.load_start_date, "%Y-%m-%d")
    end_date = datetime.strptime(args.load_end_date, "%Y-%m-%d")
    raw_table_name = args.raw_table_name

    logger.info(
        f"""
            m={JOB_NAME}, environment={env}, source={source}, raw_table_name={raw_table_name},
            load_start_date={start_date}, load_end_date={end_date}, 
            msg=print spark jobs args
        """
    )

    config_service = ConfigurationService(source)
    s3_source_bucket = config_service.get_config("s3_source_bucket")
    raw_partition_cols = config_service.get_config("raw_partition_cols")

    times_range = [(start_date + timedelta(n)) for n in range((end_date - start_date).days + 1)]

    table_data = [create_dataframe(s3_source_bucket, raw_table_name, dt) for dt in times_range]
    table_data = [i for i in table_data if i is not None]


    if len(table_data) > 0:
        
        df = reduce(
            DataFrame.unionAll, table_data
        )

        logger.info(f"m=__main__, msg={len(table_data)} of {len(times_range)} requested dates returned data for {raw_table_name}.")

        """
        Load data to datalake.
        """
        spark_client = SparkClient()
        spark_context = spark_client.conn.sparkContext
        dataframe_service = SparkDataFrameService()

        db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
        database_name = db_info["db_raw_databricks"]
        database_location = db_info["db_raw_path"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW

        spark_metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_service.create_database(database_name)

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        s3_loader = S3Loader()

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{raw_table_name}",
            format_options=format_options,
            partitions=raw_partition_cols,
            optimize_dataframe=False,
            compression="gzip",
        )

        """
        Update metastore.
        """
        spark_metastore_loader.update_metastore(
            df,
            database_name,
            raw_table_name,
            format_options,
            database_location,
            raw_partition_cols,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name, raw_table_name, df, raw_partition_cols
        )

    else:
        logger.warning(f"m=__main__, msg=No data found for table {raw_table_name} from {start_date} to {end_date}.")