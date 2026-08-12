"""Load Vector-emitted Tars / unstable-srat NDJSON logs from S3 into raw."""

from __future__ import annotations

import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta
from functools import reduce
from typing import List, Optional

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_incremental_tars_vector_logs_raw"
DAG_NAME = "tars_vector_logs"
DATE_FMT = "%Y-%m-%d"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn
metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
    spark_client
)


def inclusive_calendar_days(load_start_date: str, load_end_date: str) -> List[str]:
    """Return each calendar day from start through end as YYYY-MM-DD (inclusive)."""
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


def build_day_glob(source_bucket: str, s3_folder: str, date_str: str) -> str:
    """Build S3 glob for one UTC day: tars-logs/YYYY/MM/DD/*/*.log.gz."""
    dt = datetime.strptime(date_str, DATE_FMT)
    folder = s3_folder.rstrip("/")
    return (
        f"s3://{source_bucket}/{folder}/"
        f"{dt.year}/{dt.month:02d}/{dt.day:02d}/*/*.log.gz"
    )


def load_day_df(
    source_bucket: str, s3_folder: str, date_str: str
) -> Optional[DataFrame]:
    """Read gzipped NDJSON for one UTC day as text rows, or None if empty/missing."""
    path = build_day_glob(source_bucket, s3_folder, date_str)
    try:
        raw = spark.read.text(path)
    except Exception as exc:  # noqa: BLE001 — missing prefix is expected for sparse days
        logger.warning(
            f"m=load_day_df, date={date_str}, path={path}, "
            f"msg=No objects readable for day; skipping. exception={exc}"
        )
        return None

    if raw.rdd.isEmpty():
        logger.warning(
            f"m=load_day_df, date={date_str}, path={path}, msg=Empty read; skipping."
        )
        return None

    with_file = raw.select(
        F.input_file_name().alias("file_name"),
        F.col("value").alias("raw_content"),
    ).where(F.length(F.col("raw_content")) > 0)

    window = Window.partitionBy("file_name").orderBy(
        F.col("raw_content"), F.monotonically_increasing_id()
    )
    dt = datetime.strptime(date_str, DATE_FMT)
    return (
        with_file.withColumn("line_number", F.row_number().over(window))
        .withColumn("ts_load", F.current_timestamp())
        .withColumn("year", F.lit(dt.year))
        .withColumn("month", F.lit(dt.month))
        .withColumn("day", F.lit(dt.day))
        .select(
            "file_name",
            "line_number",
            "raw_content",
            "ts_load",
            "year",
            "month",
            "day",
        )
    )


def main() -> None:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod")
    parser.add_argument("bucket", help="datalake destination bucket")
    parser.add_argument("schema", help="custom_schema / source (tars)")
    parser.add_argument("load_start_date", help="First UTC day inclusive (YYYY-MM-DD)")
    parser.add_argument("load_end_date", help="Last UTC day inclusive (YYYY-MM-DD)")
    parser.add_argument("table_name", help="Raw table name (vector_logs)")
    parser.add_argument("partitions", help="JSON list of partition columns")
    add_validation_target_args(parser)
    args = parser.parse_args()

    environment = args.environment
    bucket = args.bucket
    schema = args.schema
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    table_name = args.table_name
    partition_cols = json.loads(args.partitions.replace("'", '"'))

    config_service = ConfigurationService(DAG_NAME)
    s3_source_bucket = config_service.get_config("s3_source_bucket")
    s3_folder = config_service.get_config("s3_folder")

    calendar_days = inclusive_calendar_days(load_start_date, load_end_date)
    logger.info(
        f"m=main, environment={environment}, schema={schema}, table_name={table_name}, "
        f"s3_source_bucket={s3_source_bucket}, s3_folder={s3_folder}, "
        f"load_start_date={load_start_date}, load_end_date={load_end_date}, "
        f"calendar_day_count={len(calendar_days)}, msg=Starting spark job"
    )

    dfs: List[DataFrame] = []
    for date_str in calendar_days:
        day_df = load_day_df(s3_source_bucket, s3_folder, date_str)
        if day_df is not None:
            dfs.append(day_df)

    if not dfs:
        logger.warning(
            f"m=main, msg=No data loaded for any day in range "
            f"{load_start_date}..{load_end_date}; skipping write and metastore"
        )
        return

    df_out = reduce(lambda left, right: left.unionByName(right), dfs)

    db_info = DatalakeMetastoreService.get_db_info(environment, schema, bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    metastore_service.create_database(write_database_name)
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)
    s3_loader = S3Loader()

    s3_loader.load_df(
        df=df_out,
        s3_path=f"{write_location}{write_table_name}",
        format_options=format_options,
        partitions=partition_cols,
        optimize_dataframe=False,
        compression="gzip",
    )

    spark_metastore_loader.update_metastore(
        df=df_out,
        database_name=write_database_name,
        table_name=write_table_name,
        format_options=format_options,
        database_location=write_location,
        partitions=partition_cols,
        force_recreate=False,
    )
    metastore_service.create_new_partitions_from_df(
        df=df_out,
        database_name=write_database_name,
        table_name=write_table_name,
        partition_cols=partition_cols,
    )

    logger.info(
        f"m=main, msg=Successfully loaded {table_name} "
        f"({len(dfs)} day(s)) into {write_database_name}"
    )


if __name__ == "__main__":
    main()
