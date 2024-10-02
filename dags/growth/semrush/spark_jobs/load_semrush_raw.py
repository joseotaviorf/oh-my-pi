from argparse import ArgumentParser

from datetime import datetime

import boto3
import json
import urllib

from pyspark.sql import DataFrame
from pyspark.sql.functions import *
from functools import reduce

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services import S3Service

def _create_dataframe_with_standard_columns(response_data: dict, display_date: str) -> DataFrame:

    data = response_data['text']
    try:
        rdd_data = sc.parallelize(data.split('\r\n'))
    except:
        return spark.createDataFrame([], schema="")

    url_parsed = urllib.parse.urlparse(response_data['url'])
    query_params = urllib.parse.parse_qs(url_parsed.query)
    if query_params['type'][0] == 'subfolder_organic':
        logger.info('Change subfolder to subdomain')
        domain = query_params['subfolder'][0]
    else:
        domain = query_params['subdomain'][0]

    df = spark.read\
        .option("inferSchema",False)\
        .option("header", "true")\
        .option("mode","FAILFAST")\
        .option("delimiter",";")\
        .csv(rdd_data)\
        .withColumn("domain", lit(domain))\
        .withColumn("date", lit(display_date))

    dt_execution = datetime.strptime(display_date, "%Y%m%d")

    df = (
              SparkDataFrameService(df)
              .format_column_names()
              .create_year_month_day_columns_from_date(dt_execution)
              .output()
          )        

    return df

def _soft_union_all(df1: DataFrame, df2: DataFrame) -> DataFrame:

    common_cols = [col for col in df1.columns if col in df2.columns] + [col for col in df2.columns if col in df1.columns]
    df1_full = df1.select(*df1.columns, *[lit(None).alias(col) for col in [col for col in df2.columns if col not in common_cols]])
    df2_full = df2.select(*df2.columns, *[lit(None).alias(col) for col in [col for col in df1.columns if col not in common_cols]])

    df = df1_full.unionByName(df2_full)

    return df

## Logger
JOB_NAME = "load_semrush_raw"
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    execution_date = datetime.strptime(args.execution_date, "%Y-%m-%d")
 
    display_date = execution_date.replace(day=15)
    display_date = display_date.strftime('%Y%m%d')

    config_service = ConfigurationService(source)
    raw_table_name = config_service.get_config("raw_table_name")
    raw_partition_cols = config_service.get_config("raw_partition_cols")

    s3_service = S3Service(boto3.resource("s3"))
    responses_folder_path = f"s3://{datalake_bucket}/{LayerEnum.RAW.value}/{source}/{display_date}/responses"

    responses_data = [
        json.loads(s3_service.read_file(file_path)) for file_path in s3_service.list_objects(responses_folder_path)
    ]
    responses_df = [
        _create_dataframe_with_standard_columns(data, display_date) for data in responses_data
    ]

    df = reduce(
        _soft_union_all, responses_df
    )

    if df:
        """
        Load data to datalake.
        """
        spark_client = SparkClient()
        spark_context = spark_client.conn.sparkContext
        dataframe_service = SparkDataFrameService()

        db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
        database_name = db_info["db_raw_databricks"]
        database_location = db_info["db_raw_path"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW

        spark_metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_service.create_database(database_name)

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        s3_loader = S3Loader()

        s3_loader.load_df(
            df=df,
            format_options=SparkTableStorageFormat.DEFAULT_RAW,
            s3_path=f"{database_location}{raw_table_name}",
            partitions=raw_partition_cols,
            compression="gzip"
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=raw_table_name,
            format_options=SparkTableStorageFormat.DEFAULT_RAW,
            database_location=database_location,
            partitions=raw_partition_cols,
            force_recreate=True,
        )

        spark_metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=database_name,
            table_name=raw_table_name,
            partition_cols=raw_partition_cols,
        )
    else:
        raise Exception(f"m=Failed to ingest data for display_limit='{display_date}'.")