import json
import logging
import re
from argparse import ArgumentParser
from collections import defaultdict
from datetime import datetime, timedelta, timezone
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
from bietlejuice.services.metastore_services import MetastoreServiceFactory
from bietlejuice.services.storage_services.s3_service import S3Service

JOB_NAME = "load_invoice_preview_into_datalake"

# SeuBarriga morning export ~01:00 BRT and can last several hours; afternoon export
# starts at 12:00 BRT on billing days (22nd through month-end). Batches are split by
# the Unix timestamp prefix in the CSV name (hour BRT < 12 morning, else afternoon),
# matching clean export_slot. Do not split a long morning dump by a sliding window:
# that treated the first shards as "morning" and dropped the rest on the 09:00 overwrite.
# Morning DAG runs overwrite the partition; afternoon runs append afternoon CSVs only
# when a separate afternoon batch exists on S3 (days 1-21 usually skip the raw write).
EXPORT_SLOT_MORNING = "morning"
EXPORT_SLOT_AFTERNOON = "afternoon"
EXPORT_SLOT_AUTO = "auto"
BRT = timezone(timedelta(hours=-3))
# SeuBarriga preview audit columns (CSV kebab-case). Older files may omit them;
# fill nulls so unionAll across mixed schemas does not fail.
PREVIEW_AUDIT_CSV_COLUMNS = (
    "last-modified-by-name",
    "last-modified-by-email",
    "created-at",
)

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_dbutils():
    return BaseDBUtils().get_dbutils()


def _file_timestamp(path):
    return int(path.split("/")[-1].split("-")[0])


def _file_datetime_brt(path):
    return datetime.fromtimestamp(_file_timestamp(path), tz=timezone.utc).astimezone(
        BRT
    )


def _select_latest_export_batch(file_paths):
    afternoon_batch = [
        path for path in file_paths if _file_datetime_brt(path).hour >= 12
    ]
    logger.info(
        f"m=_select_latest_export_batch, total_files={len(file_paths)}, "
        f"afternoon_batch_files={len(afternoon_batch)}, "
        f"msg=Selected afternoon export batch (hour BRT >= 12)."
    )
    return afternoon_batch


def _select_morning_export_batch(file_paths):
    morning_batch = [path for path in file_paths if _file_datetime_brt(path).hour < 12]
    logger.info(
        f"m=_select_morning_export_batch, total_files={len(file_paths)}, "
        f"morning_batch_files={len(morning_batch)}, "
        f"msg=Selected morning export batch (hour BRT < 12)."
    )
    return morning_batch


def _resolve_export_slot(export_slot):
    if export_slot in (EXPORT_SLOT_MORNING, EXPORT_SLOT_AFTERNOON):
        return export_slot

    if export_slot not in (None, "", EXPORT_SLOT_AUTO):
        raise ValueError(
            f"Invalid export_slot={export_slot!r}; "
            f"expected morning, afternoon, or auto."
        )

    local_hour = datetime.now(BRT).hour
    resolved = EXPORT_SLOT_AFTERNOON if local_hour >= 12 else EXPORT_SLOT_MORNING
    logger.info(
        f"m=_resolve_export_slot, inferred_export_slot={resolved}, "
        f"local_hour_brt={local_hour}, msg=Inferred export slot from job start time."
    )
    return resolved


def _select_files_for_export_slot(file_paths, export_slot):
    morning_batch = _select_morning_export_batch(file_paths)
    latest_batch = _select_latest_export_batch(file_paths)

    if export_slot == EXPORT_SLOT_MORNING:
        if morning_batch:
            selected = morning_batch
        else:
            selected = latest_batch
        logger.info(
            f"m=_select_files_for_export_slot, export_slot={export_slot}, "
            f"selected_files={len(selected)}, msg=Selected morning export files."
        )
        return selected

    if not morning_batch:
        logger.warning(
            f"m=_select_files_for_export_slot, export_slot={export_slot}, "
            f"msg=No separate afternoon batch on S3; skipping afternoon load."
        )
        return []

    selected = latest_batch
    logger.info(
        f"m=_select_files_for_export_slot, export_slot={export_slot}, "
        f"selected_files={len(selected)}, msg=Selected afternoon export files."
    )
    return selected


def _write_mode_for_export_slot(export_slot):
    return "append" if export_slot == EXPORT_SLOT_AFTERNOON else "overwrite"


def _ensure_string_columns(df, column_names):
    for column_name in column_names:
        if column_name not in df.columns:
            df = df.withColumn(column_name, functions.lit(None).cast("string"))
    return df


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
    parser.add_argument(
        "--export-slot",
        choices=[
            EXPORT_SLOT_MORNING,
            EXPORT_SLOT_AFTERNOON,
            EXPORT_SLOT_AUTO,
        ],
        default=EXPORT_SLOT_AUTO,
        help=(
            "SeuBarriga export batch for this run. Use auto to infer from "
            "America/Sao_Paulo hour at job start (before 12: morning, else afternoon). "
            "Airflow manual runs may pass morning or afternoon via dag_run.conf."
        ),
    )

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
    export_slot = _resolve_export_slot(args.export_slot)
    write_mode = _write_mode_for_export_slot(export_slot)

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                source_root_path={source_root_path}, load_start_date={load_start_date}, load_end_date={load_end_date},
                table_name={table_name}, format={format}, options = {options}, export_slot={export_slot},
                write_mode={write_mode}, msg=Starting spark job...
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
        yearmonthday = _file_datetime_brt(path).strftime("%Y-%m-%d")
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
            csv_files = _select_files_for_export_slot(
                by_day_files[date_ingested], export_slot
            )
            if not csv_files:
                continue

            for csv in csv_files:
                df = s3_consumer.get_data_from_file(
                    path=csv, format=format, options=options
                )
                df = _ensure_string_columns(df, PREVIEW_AUDIT_CSV_COLUMNS)
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
            spark_metastore_service = (
                MetastoreServiceFactory.create_loader_metastore_service(spark_client)
            )
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
                write_mode=write_mode,
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

        gchat_webhook = get_dbutils().secrets.get(scope="quintoandar", key=key)
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
