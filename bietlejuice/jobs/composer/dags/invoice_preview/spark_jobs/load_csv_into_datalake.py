from collections import defaultdict
from datetime import datetime
from functools import reduce
import json
import logging
from argparse import ArgumentParser
import re

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import (
    SparkTableStorageFormat,
    BaseDBUtils,
    SparkDataFrameService,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.s3_consumer import S3Consumer
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader

from bietlejuice.jobs.composer.services.s3_service import S3Service

import boto3
from pyspark.sql import DataFrame, functions


JOB_NAME = "load_csv_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("source_root_path", help="name of the source")
    parser.add_argument(
        "date_to_ingest",
        help="Date to be used in filtering the files. Format: '%Y-%m-%d'",
    )
    parser.add_argument("table_name", help="name of the output table")
    parser.add_argument(
        "consumer_extra_args",
        help="extra arguments to pass to get_data_from_file of S3Consumer",
    )

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    source_root_path = args.source_root_path
    date_to_ingest = args.date_to_ingest
    table_name = args.table_name
    consumer_extra_args = json.loads(args.consumer_extra_args)
    partition_cols = ["year", "month", "day"]
    date_ingested = datetime.strptime(date_to_ingest, "%Y-%m-%d")

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                source_root_path={source_root_path}, date_to_ingest={date_to_ingest}, table_name={table_name},
                consumer_extra_args={consumer_extra_args}, msg=Starting spark job...
        """
    )

    # Initializing clients
    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    # Retrieving folders/tables from root location.
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    files = S3Service(boto3.resource("s3")).list_objects(source_root_path)
    pattern = re.compile(r".*/.*preview.*")
    filtered_files = list(filter(pattern.match, files))

    by_day_files = defaultdict(list)

    for path in filtered_files:
        timestamp = int(path.split("/")[-1].split("-")[0])
        yearmonthday = datetime.fromtimestamp(timestamp).strftime("%Y-%m-%d")
        by_day_files[yearmonthday].append(path)

    dfs = []
    for csv in by_day_files[date_to_ingest]:
        dfs.append(s3_consumer.get_data_from_file(path=csv, **consumer_extra_args))
    df = reduce(DataFrame.unionAll, dfs)
    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_date(date_ingested)
        .output()
    )

    df = df.withColumn("ts_load", functions.current_timestamp())

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()

    s3_path = f"{database_location}{table_name}"

    s3_loader.load_df(
        df=df, s3_path=s3_path, format_options=format_options, partitions=partition_cols
    )

    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location, partition_cols
    )

    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=df,
        partition_cols=partition_cols,
    )
