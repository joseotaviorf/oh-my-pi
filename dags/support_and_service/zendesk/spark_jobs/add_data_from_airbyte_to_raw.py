import json
import logging
import multiprocessing
import concurrent.futures

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

from pyspark.sql.functions import lit

JOB_NAME = "add_data_from_airbyte_to_raw"
SOURCE = "zendesk"

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("execution_date")
    parser.add_argument("next_execution_date")
    parser.add_argument("table_name")

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name
    partition_cols = json.loads(args.partition_cols)
    execution_date_str = args.execution_date
    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")

    proxy_path = f"s3://5a-datalake-prod/airbyte/zendesk_{table_name}/{table_name}/{execution_date_str.replace('-', '_')}_*"

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(spark_client)

    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    df = s3_consumer.get_data_from_file(
        proxy_path,
        format="json",
    ).select("_airbyte_data.*").drop('metadata') # this column exists on ticket_audits and causes schema errors

    df = df.withColumn("dt", lit(execution_date_str.replace('-', '_')))

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
