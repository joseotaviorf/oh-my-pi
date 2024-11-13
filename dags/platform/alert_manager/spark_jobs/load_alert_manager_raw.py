from argparse import ArgumentParser

import json
from datetime import datetime, timedelta

from pyspark.sql import DataFrame
from functools import reduce

import logging
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_alert_manager_raw"

logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    start_date = datetime.strptime(args.load_start_date, "%Y-%m-%d")
    end_date = datetime.strptime(args.load_end_date, "%Y-%m-%d")

    config_service = ConfigurationService(source)
    raw_table_name = config_service.get_config("raw_table_name")
    raw_partition_cols = config_service.get_config("raw_partition_cols")

    alert_manager_folder = config_service.get_config("alert_manager_folder")

    """
    Fetch AlertManager alerts data.
    """
    path_template = "s3://{}/raw/{}/year={}/month={}/day={}"

    times_range = [start_date + timedelta(n) for n in range((end_date - start_date).days + 1)]
    dates_range = [[str(dt.year),str(dt.month).zfill(2),str(dt.day).zfill(2)] for dt in times_range]
    paths_range = [path_template.format(datalake_bucket,alert_manager_folder,*dt) for dt in dates_range]

    dfs_range = [spark.read.json(path) for path in paths_range]

    dfs_filtered = filter(lambda df: df.rdd.isEmpty,dfs_range)

    df = reduce(
        DataFrame.unionAll, dfs_filtered
    )

    """
    Creating dataframe.
    """
    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column("@timestamp")
        .output()
    )        

    df = df.na.drop(subset=raw_partition_cols)

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
        force_recreate=True,
    )

    spark_metastore_service.create_new_partitions_from_df(
        database_name, raw_table_name, df, raw_partition_cols
    )