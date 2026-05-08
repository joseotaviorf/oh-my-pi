import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta
from functools import reduce
from typing import List

from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_offboarding_categorization_raw"

DATE_FMT = "%Y-%m-%d"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

PERSISTED_COLUMNS = [
    "id_langfuse_session",
    "session_date",
    "first_queue",
    "last_queue",
    "is_offboarding",
    "is_escalated",
    "offboarding_category",
    "reasoning",
]


def get_forno_adjusted_data_science_path(environment: str, source_root_path: str) -> str:
    """Resolve data-science bucket host for forno vs prod."""
    if environment == "forno":
        return source_root_path.replace(
            "s3://data-science.s3.data", "s3://data-science.s3.forno.data"
        )
    return source_root_path


def build_session_metadata_parquet_uri(source_root_path: str, date_to_ingest: str) -> str:
    """Build S3 URI for one daily parquet (session-metadata/{yyyy-MM-dd}.parquet)."""
    base = source_root_path.rstrip("/")
    return f"{base}/{date_to_ingest}.parquet"


def inclusive_calendar_days(load_start_date: str, load_end_date: str) -> List[str]:
    """Return each calendar day from load_start_date through load_end_date as YYYY-MM-DD (inclusive)."""
    dt_start = datetime.strptime(load_start_date, DATE_FMT).date()
    dt_end = datetime.strptime(load_end_date, DATE_FMT).date()
    if dt_start > dt_end:
        raise ValueError(
            f"load_start_date ({load_start_date}) must be <= load_end_date ({load_end_date})"
        )
    out: List[str] = []
    current = dt_start
    while current <= dt_end:
        out.append(current.strftime(DATE_FMT))
        current += timedelta(days=1)
    return out


def _prepare_day_df(df, date_str):
    missing_cols = [c for c in PERSISTED_COLUMNS if c not in df.columns]
    if missing_cols:
        raise ValueError(
            f"m=load_day, date={date_str}, msg=Parquet schema missing expected columns: "
            f"{missing_cols}"
        )

    dt_execution = datetime.strptime(date_str, DATE_FMT)
    out = df.select(*PERSISTED_COLUMNS)
    out = out.withColumn("ts_load", F.current_timestamp())
    out = (
        out.withColumn("year", F.lit(dt_execution.year))
        .withColumn("month", F.lit(dt_execution.month))
        .withColumn("day", F.lit(dt_execution.day))
    )
    return out


def main() -> None:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source (dag name)")
    parser.add_argument(
        "source_root_path",
        help="S3 directory for session-metadata parquet files (no trailing date)",
    )
    parser.add_argument(
        "load_start_date",
        help="First calendar day to load (inclusive). Format: YYYY-MM-DD",
    )
    parser.add_argument(
        "load_end_date",
        help="Last calendar day to load (inclusive). Format: YYYY-MM-DD",
    )
    parser.add_argument("table_name", help="name of the output table")
    parser.add_argument("partitions", help="list with partition cols")
    parser.add_argument("format", help="data format to load from S3")

    args = parser.parse_args()
    environment = args.environment
    bucket = args.bucket
    source = args.source
    source_root_path = get_forno_adjusted_data_science_path(
        environment, args.source_root_path
    )
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    table_name = args.table_name
    partition_cols = json.loads(args.partitions.replace("'", '"'))
    data_format = args.format

    calendar_days = inclusive_calendar_days(load_start_date, load_end_date)

    logger.info(
        f"m=main, environment={environment}, source={source}, table_name={table_name}, "
        f"load_start_date={load_start_date}, load_end_date={load_end_date}, "
        f"calendar_day_count={len(calendar_days)}, msg=Starting spark job..."
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    s3_loader = S3Loader()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.PARQUET

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=main, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    dfs = []
    for date_str in calendar_days:
        parquet_uri = build_session_metadata_parquet_uri(source_root_path, date_str)
        try:
            raw_df = s3_consumer.get_data_from_file(parquet_uri, data_format)
        except Exception as exc:
            logger.warning(
                f"m=main, msg=No parquet loaded for date (missing or unreadable file). "
                f"uri={parquet_uri}, exception={exc}"
            )
            continue

        day_df = _prepare_day_df(raw_df, date_str)

        if day_df.rdd.isEmpty():
            logger.warning(
                f"m=main, msg=Parquet for {date_str} is empty; skipping that day."
            )
            continue
        dfs.append(day_df)

    if not dfs:
        logger.warning(
            f"m=main, msg=No data loaded for any day in range "
            f"{load_start_date}..{load_end_date}; skipping S3 write and metastore."
        )
        return

    df_out = reduce(lambda a, b: a.unionByName(b), dfs)

    s3_loader.load_df(
        df=df_out,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )

    spark_metastore_loader.update_metastore(
        df=df_out,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
        partitions=partition_cols,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df_out,
        database_name=database_name,
        table_name=table_name,
        partition_cols=partition_cols,
    )

    logger.info(
        f"m=main, msg=Successfully loaded {table_name} "
        f"({len(dfs)} day(s)) into datalake"
    )


if __name__ == "__main__":
    main()
