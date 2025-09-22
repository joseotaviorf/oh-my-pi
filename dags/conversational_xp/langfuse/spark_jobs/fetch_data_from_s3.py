import logging
import re
from argparse import ArgumentParser
from datetime import datetime, timedelta

import boto3
from pyspark.sql.functions import lit, to_json, col

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services import S3Service


JOB_NAME = "load_langfuse_raw"
SOURCE = "langfuse"

logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s:%(name)s:%(asctime)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = logging.getLogger(JOB_NAME)

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

    logger.info(
        f"dag_name={dag_name}, datalake_bucket={datalake_bucket}, table_name={table_name}, "
        f"start_timestamp={start_timestamp_str}, end_timestamp={end_timestamp_str}"
    )

    config_service = ConfigurationService(dag_name)
    langfuse_integration_bucket_path = config_service.get_config("langfuse_integration_bucket_path")
    proxy_path = f"{langfuse_integration_bucket_path}{table_name}"

    end_timestamp = datetime.fromisoformat(end_timestamp_str).replace(tzinfo=None)
    start_timestamp = datetime.fromisoformat(start_timestamp_str).replace(tzinfo=None)
    partition_cols = ["year", "month", "day", "hour"]

    hours_diff = int((end_timestamp - start_timestamp) / timedelta(hours=1)) + 1
    timestamp_strs = [
        (start_timestamp + timedelta(hours=i)).strftime("%Y-%m-%dT%H*") for i in range(hours_diff)
    ]

    spark_client = SparkClient()
    s3_loader = S3Loader()
    s3_service = S3Service(boto3.resource("s3"))
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    objs = s3_service.list_objects(proxy_path)
    timestamp_patterns = [re.compile(ts_str.replace('*', '.*')) for ts_str in timestamp_strs]
    valid_files = [
        filename for filename in objs if any(
            pattern.search(filename) for pattern in timestamp_patterns
        )
    ]
    logger.info(f"Found {len(valid_files)} files")
    if valid_files:

        df = spark.read.json(valid_files)

        if df.isEmpty():
            logger.warning(f"Dataframe is empty for table {table_name} between {start_timestamp} and {end_timestamp}. Skipping data loading operations.")
        else:
            if "metadata" in df.columns:
                df = df.withColumn("metadata", to_json(col("metadata")))
            
            df = (
                df.withColumn("year", lit(start_timestamp.year))
                .withColumn("month", lit(start_timestamp.month))
                .withColumn("day", lit(start_timestamp.day))
                .withColumn("hour", lit(start_timestamp.hour))
            )

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
    else:
        logger.warning(f"No files found between {start_timestamp} and {end_timestamp}")
