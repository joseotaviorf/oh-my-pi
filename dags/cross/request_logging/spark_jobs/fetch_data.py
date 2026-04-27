import json
import logging
import re
import time
import random
import threading
from argparse import ArgumentParser
from collections import deque
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed

from pyspark.sql import functions as F
from pyspark.sql.types import FloatType, StringType, StructField, StructType

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
)
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.storage_services import S3Service


DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "fetch_data"
SOURCE = "request_logging"


logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s:%(name)s:%(asctime)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = logging.getLogger(JOB_NAME)

def fetch_from_s3(spark, proxy_path, start_timestamp, end_timestamp, table_name):
    logger.info(f"Fetching data from S3 for table: {table_name}, path: {proxy_path}")

    # Calculate difference in days between start and end dates
    delta = end_timestamp - start_timestamp
    num_days = delta.days + 1 #+1 to include the end date

    paths_to_load = []

    # Iterate over the number of days
    for i in range(num_days):
        current_date = start_timestamp + timedelta(days=i)

        # Build the path
        path = proxy_path.format(
            table_name,
            current_date.year,
            str(current_date.month).zfill(2),
            str(current_date.day).zfill(2)
        )
        # Check if the path exists in S3 before including
        try:
            dbutils.fs.ls(path.replace("/*", ""))
            paths_to_load.append(path)
        except Exception as e:
            logger.warning(f"Error checking path {path}: {str(e)}")

    # Unified loading if there are paths to load
    if len(paths_to_load) > 0:
        df = spark.read.format("json").load(paths_to_load)
    else:
        logger.warning(f"Dataframe is empty for table {table_name} between {start_timestamp} and {end_timestamp}. Skipping data loading operations.")
        df = None
    return df

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name")
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("start_timestamp")
    parser.add_argument("end_timestamp")
    parser.add_argument("table_name")

    args = parser.parse_args()
    dag_name = args.dag_name
    environment = args.env
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name
    start_timestamp_str = args.start_timestamp
    end_timestamp_str = args.end_timestamp

    logger.info(f"dag_name={dag_name}, environment={environment}, datalake_bucket={datalake_bucket}")
    logger.info(f"table_name={table_name}")
    logger.info(f"start_timestamp={start_timestamp_str}, end_timestamp={end_timestamp_str}")

    end_timestamp = datetime.fromisoformat(end_timestamp_str).replace(tzinfo=None)
    start_timestamp = datetime.fromisoformat(start_timestamp_str).replace(tzinfo=None) - timedelta(days=1)
    partition_cols = ["year", "month", "day"]

    config_service = ConfigurationService(dag_name)
    spark_client = SparkClient()
    spark = spark_client.conn
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader = S3Loader()

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, SOURCE, datalake_bucket
    )
    database_name = datalake_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    proxy_path = config_service.get_config("request_logging_bucket_path")

    df = fetch_from_s3(spark, proxy_path, start_timestamp, end_timestamp, table_name)

    if df is None:
        logger.warning(f"No data to process for table {table_name}")
    else:
        df = (
            df.withColumn("year", F.lit(start_timestamp.year)) # add year partition
            .withColumn("month", F.lit(start_timestamp.month)) # add month partition
            .withColumn("day", F.lit(start_timestamp.day)) # add day partition
            .withColumn("hour", F.lit(start_timestamp.hour)) # add hour partition
        )

        cols_structs = [c.name for c in df.schema if isinstance(c.dataType, StructType)] # get all struct columns
        for col_name in cols_structs:
            df = df.withColumn(col_name, F.to_json(F.col(col_name))) # cast from struct to string keeping json format

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols,
            optimize_dataframe=False,
            compression="gzip",
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
            partitions=partition_cols,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=database_name,
            table_name=table_name,
            partition_cols=partition_cols,
        )

        full_raw_table_name = f"datalake_{SOURCE}_raw.{table_name}"
        table_privileges = TablePrivileges.from_environment_default(full_raw_table_name)
        if (
            table_privileges
            and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
        ):
            table_privileges.apply()

        logger.info(f"Successfully processed and loaded data for table {table_name}")
