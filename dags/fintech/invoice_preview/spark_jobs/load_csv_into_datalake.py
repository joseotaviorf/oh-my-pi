import json
import logging
import re
from argparse import ArgumentParser
from collections import defaultdict
from datetime import datetime, timedelta
from functools import reduce

import boto3
from pyspark.sql import DataFrame, functions
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.storage_services.s3_service import S3Service

JOB_NAME = "load_invoice_preview_into_datalake"

# SeuBarriga afternoon export starts at 12:00 and may take up to 4h30.
# Keep every file from the latest batch when multiple exports land on the same day.
LATEST_EXPORT_BATCH_WINDOW_SECONDS = 5 * 3600

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def _file_timestamp(path):
    return int(path.split("/")[-1].split("-")[0])


def _select_latest_export_batch(file_paths):
    if not file_paths:
        return []

    max_ts = max(_file_timestamp(path) for path in file_paths)
    batch_threshold = max_ts - LATEST_EXPORT_BATCH_WINDOW_SECONDS
    latest_batch = [
        path for path in file_paths if _file_timestamp(path) >= batch_threshold
    ]

    logger.info(
        f"m=_select_latest_export_batch, total_files={len(file_paths)}, "
        f"latest_batch_files={len(latest_batch)}, max_ts={max_ts}, "
        f"batch_threshold={batch_threshold}, msg=Selected latest export batch."
    )
    return latest_batch


def _generate_date_range(load_start_date, load_end_date):
    start_date = datetime.strptime(load_start_date, "%Y-%m-%d")
    end_date = datetime.strptime(load_end_date, "%Y-%m-%d")
    date_index = [
        start_date + timedelta(days=x)
        for x in range(0, (end_date - start_date).days + 1)
    ]
    return date_index


def __build_warning_messages(
    environment,
    s3_path_prefix,
    table_name,
    dates,
):

    messages = []
    for date in dates:
        messages.append(
            f"⚠️\n"
            f"Environment: *{environment}*\n"
            f"Table: `{s3_path_prefix}/{table_name}`\n"
            f"Status: *FAILED*\n"
            f"Existence validation failed for `{date}`\n"
        )

    return messages


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("source_root_path", help="source root path")
    parser.add_argument(
        "load_start_date",
        help="Start of date range to be used in filtering the files. Format: '%Y-%m-%d'",
    )
    parser.add_argument(
        "load_end_date",
        help="End of date range to be used in filtering the files. Format: '%Y-%m-%d'",
    )
    parser.add_argument("table_name", help="name of the output table")
    parser.add_argument("file_format", help="file format")
    parser.add_argument("file_options", help="file options")

    add_validation_target_args(parser)
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    source_root_path = args.source_root_path
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    table_name = args.table_name
    format = args.file_format
    options = json.loads(args.file_options)
    partition_cols = ["year", "month", "day"]

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                source_root_path={source_root_path}, load_start_date={load_start_date}, load_end_date={load_end_date},
                table_name={table_name}, format={format}, options = {options}, msg=Starting spark job...
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
        yearmonthday = datetime.fromtimestamp(_file_timestamp(path)).strftime(
            "%Y-%m-%d"
        )
        by_day_files[yearmonthday].append(path)

    days_to_send_warning = []
    dates_to_ingest = _generate_date_range(load_start_date, load_end_date)
    for date_to_ingest in dates_to_ingest:
        dfs = []
        date_ingested = date_to_ingest.strftime("%Y-%m-%d")
        if len(by_day_files[date_ingested]) <= 0:
            logger.warning(
                "m=__main__, msg= No files were found on S3 bucket. Ending process without loading anything."
            )
            days_to_send_warning.append(date_ingested)
        else:
            csv_files = _select_latest_export_batch(by_day_files[date_ingested])
            for csv in csv_files:
                df = s3_consumer.get_data_from_file(
                    path=csv, format=format, options=options
                )
                df = df.withColumn("invoice_filename", functions.lit(csv))
                dfs.append(df)

            df = reduce(DataFrame.unionAll, dfs)
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_date(date_to_ingest)
                .output()
            )

            df = df.withColumn("ts_load", functions.current_timestamp())

            db_info = DatalakeMetastoreService.get_db_info(
                environment, source, datalake_bucket
            )
            spark_metastore_service = SparkMetastoreService(spark_client)
            spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

            logger.info(
                "m=__main__, msg=Creating database in Spark Metastore if not exists..."
            )
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

            s3_loader = S3Loader()

            s3_path = f"{write_location}{write_table_name}"

            s3_loader.load_df(
                df=df,
                s3_path=s3_path,
                format_options=format_options,
                partitions=partition_cols,
            )

            spark_metastore_loader.update_metastore(
                df,
                write_database_name,
                write_table_name,
                format_options,
                write_location,
                partition_cols,
            )

            spark_metastore_service.create_new_partitions_from_df(
                database_name=write_database_name,
                table_name=write_table_name,
                df=df,
                partition_cols=partition_cols,
            )

    if days_to_send_warning:
        if environment == "prod":
            key = GchatWebhooksEnum.FINTECH_ALERTS_PROD
        else:
            key = GchatWebhooksEnum.AE_ALERTS_FORNO

        gchat_webhook = dbutils.secrets.get(scope="quintoandar", key=key)
        messages = __build_warning_messages(
            environment=environment,
            s3_path_prefix=f"s3://{source_root_path}",
            table_name=table_name,
            dates=days_to_send_warning,
        )
        for message_content in messages:
            message = Message(content=message_content, destination=gchat_webhook)
            logger.info(f"m=__main__, message=sending slack message: {message}")
            GChatService.send_message(message)
