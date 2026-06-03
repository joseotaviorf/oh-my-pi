import logging
from argparse import ArgumentParser
from datetime import datetime

import boto3
from pyspark.sql.functions import lit
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.storage_services import S3Service

JOB_NAME = "add_data_from_airbyte_to_raw"
SOURCE = "zendesk"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("execution_date")
    parser.add_argument("next_execution_date")
    parser.add_argument("table_name")

    add_validation_target_args(parser)
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name
    execution_date_str = args.execution_date
    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")

    proxy_path = f"s3://5a-datalake-incoming-prod/airbyte/zendesk_{table_name}/{table_name}/{execution_date_str.replace('-', '_')}_*"

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    s3_loader = S3Loader()
    s3_service = S3Service(boto3.resource("s3"))
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )
    spark_metastore_service.create_database(write_database_name)

    objs = s3_service.list_objects(
        f"s3://5a-datalake-incoming-prod/airbyte/zendesk_{table_name}/{table_name}"
    )
    valid_files = [
        filename
        for filename in objs
        if f"{execution_date_str.replace('-', '_')}" in filename
    ]
    if valid_files:
        df = (
            s3_consumer.get_data_from_file(
                valid_files,
                format="json",
            )
            .select("_airbyte_data.*")
            .drop("metadata")
        )  # this column exists on ticket_audits and causes schema errors

        df = df.withColumn("dt", lit(execution_date_str))

        s3_loader.load_df(
            df=df,
            s3_path=f"{write_location}{write_table_name}",
            format_options=format_options,
            partitions=["dt"],
            optimize_dataframe=False,
            compression="gzip",
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=write_database_name,
            table_name=write_table_name,
            format_options=format_options,
            database_location=write_location,
            partitions=["dt"],
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=write_database_name,
            table_name=write_table_name,
            partition_cols=["dt"],
        )
    else:
        logger.info(f"No files found for date {execution_date_str}")
