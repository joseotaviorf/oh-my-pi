import logging
from argparse import ArgumentParser
from functools import reduce
import datetime as datetime

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

JOB_NAME = "load_union_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

client = boto3.client('s3')
def _checkPath(source_bucket: str, file_path: str) -> DataFrame:
  result = client.list_objects(Bucket=source_bucket, Prefix=file_path)
  exists = False
  if 'Contents' in result:
      exists = True
  return exists


def _create_dataframe(s3_source_bucket: str, raw_table_name:str, date: datetime, date_increment_col: str) -> DataFrame:
    file_path = f"{raw_table_name}/{date.year}/{date.month:01}/{date.day:01}"
    df = None
    logger.info("msg=Trying to read data from s3://{s3_source_bucket}/{file_path}/")
    if _checkPath(s3_source_bucket, file_path):
        df = spark_client.conn.read.option("header", True).option("delimiter",";").option("multiline", True).csv(f"s3://{s3_source_bucket}/{file_path}/*")
        if df is not None:
            df = (df_service
            .input(df)
            .create_year_month_day_columns_from_dataframe_column(date_increment_col)
            .convert_struct_type_to_json()
            .output()
            )

            logger.info(f"""m=_create_dataframe, source_bucket={s3_source_bucket}, table_name={raw_table_name}, msg=Succesfully got data from s3://{s3_source_bucket}/{file_path}/""")
            return df
        
        logger.warning(f"m=_create_dataframe, msg=Empty bucket for s3://{s3_source_bucket}/{file_path}/")
    return None


def _generate_date_range(load_start_date, load_end_date):
    start_date = datetime.datetime.strptime(load_start_date, "%Y-%m-%d")
    end_date = datetime.datetime.strptime(load_end_date, "%Y-%m-%d")
    date_index = [start_date + datetime.timedelta(days=x) for x in range(0, (end_date - start_date).days + 1)]

    logger.info(
        f"""m=_generate_date_range, msg=Getting data from {start_date} to {end_date}..."""
    )

    return date_index

logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("source")
    parser.add_argument("raw_table_name")
    parser.add_argument("date_increment_col")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.env}, source={args.source}, 
            raw_table_name={args.raw_table_name}, date_increment_col={args.date_increment_col},
            load_start_date={args.load_start_date},load_end_date={args.load_end_date}
            msg=print spark jobs args
        """
    )

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    date_increment_col = args.date_increment_col
    raw_table_name = args.raw_table_name
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date

    config_service = ConfigurationService(source)
    s3_source_bucket = config_service.get_config("s3_source_bucket")
    raw_partition_cols = config_service.get_config("raw_partition_cols")

    spark_client = SparkClient()
    spark_context = spark_client.conn.sparkContext
    df_service = SparkDataFrameService()

    logger.info(f"""m={JOB_NAME}, source_bucket={s3_source_bucket}, table_name={raw_table_name}, msg=Getting data from bucket...""")
    
    time_range = _generate_date_range(load_start_date=load_start_date, load_end_date = load_end_date)

    table_data = [_create_dataframe(s3_source_bucket, raw_table_name, date, date_increment_col) for date in time_range]
    table_data = [i for i in table_data if i is not None]

    if len(table_data) > 0:
        df = reduce(
            DataFrame.unionAll, table_data
        )

        logger.info(f"m=__main__, msg={len(table_data)} of {len(time_range)} requested dates returned data for {raw_table_name}.")

        """
        Load data to datalake.
        """
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
       logger.warning(f"m=__main__, msg={len(table_data)} of {len(time_range)} requested dates returned data for {raw_table_name}.")