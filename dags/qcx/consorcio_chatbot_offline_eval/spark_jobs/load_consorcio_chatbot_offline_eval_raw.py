#!/usr/bin/env python3
"""Load Consórcio chatbot offline-eval JSON artifacts from S3 into raw Delta.

Source layout (host- and suite-agnostic):
  {source_root_path}/{host_name}/atenas/{suite_name}/date=YYYY-MM-DD/commit=<sha>/<run_ts>.json

Lean raw grain: one row per S3 file (s3_path, git_commit, ts_eval, result_json).
Path semantics (host/suite/id_eval_run) and metric indexing live in clean SQL.

Incremental discovery (watermark + bounded list):
  1. Read max(dt_eval) from the raw table (path date of the latest ingested file).
  2. List only */atenas/*/date={d}/commit=*/*.json for d from that watermark
     (inclusive) through today — S3 LIST stays proportional to recent days,
     not the full history.
  3. Anti-join those paths against s3_path already in raw for the same date
     range (same-day re-runs / partial days) and read only the remainder.
  Bootstrap (empty / missing table): list from load_start_date; if nothing to
  load, still create an empty Delta table so sync-metadata and clean can run.
  Insert-only MERGE on s3_path keeps the load idempotent.
"""

from __future__ import annotations

import argparse
import ast
from datetime import date, datetime, timedelta
from typing import List, Optional, Set

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (
    DateType,
    IntegerType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_consorcio_chatbot_offline_eval_raw"
DAG_NAME = "consorcio_chatbot_offline_eval"
DATE_FMT = "%Y-%m-%d"
MERGE_ON = ["s3_path"]
# Per-day glob under the source root (host/suite wildcards).
DAY_GLOB = "*/atenas/*/date={day}/commit=*/*.json"
# date=YYYY-MM-DD / commit=<sha> / <run_ts>.json (host/suite ignored here)
PATH_PATTERN = (
    r"chatbot/[^/]+/atenas/[^/]+/date=([0-9]{4}-[0-9]{2}-[0-9]{2})"
    r"/commit=([^/]+)/([^/]+)\.json$"
)
TS_EVAL_FORMAT = "yyyyMMdd'T'HHmmss'Z'"

logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn
metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
    spark_client
)


def parse_args() -> argparse.Namespace:
    arg_parser = argparse.ArgumentParser(description=JOB_NAME)
    arg_parser.add_argument("environment", help="forno or prod")
    arg_parser.add_argument(
        "bucket", help="5a-datalake-<env> bucket name or full s3:// path"
    )
    arg_parser.add_argument(
        "schema", help="Schema name without datalake_ prefix or _raw suffix"
    )
    arg_parser.add_argument("table_name", help="Raw table name")
    arg_parser.add_argument("partitions", help="e.g. ['year','month','day']")
    arg_parser.add_argument(
        "load_start_date",
        help=(
            "YYYY-MM-DD: empty-table bootstrap floor, and optional lookback "
            "override when earlier than max(dt_eval) in raw"
        ),
    )
    add_validation_target_args(arg_parser)
    args = arg_parser.parse_args()
    args.partition_cols = ast.literal_eval(args.partitions)
    return args


def main() -> None:
    args = parse_args()
    conf = ConfigurationService(DAG_NAME)
    source_root = conf.get_config("source_root_path").rstrip("/")

    bucket = args.bucket.replace("s3://", "").replace("s3a://", "")
    db_info = DatalakeMetastoreService.get_db_info(
        args.environment, args.schema, bucket
    )
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=db_info["db_raw_databricks"],
            prod_table=args.table_name,
            prod_location=db_info["db_raw_path"],
            bucket=bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )
    full_table_name = f"{write_database_name}.{write_table_name}"

    watermark = _watermark_dt_eval(spark, full_table_name)
    bootstrap = datetime.strptime(args.load_start_date, DATE_FMT).date()
    # Steady state: list from the watermark day (inclusive). Empty table: bootstrap
    # from load_start_date. Conf override of load_start_date to an older day forces
    # a deeper lookback / backfill without changing the watermark logic.
    list_start = watermark or bootstrap
    if bootstrap < list_start:
        logger.info(
            f"m=main, msg=load_start_date overrides watermark lookback, "
            f"bootstrap={bootstrap}, watermark={watermark}"
        )
        list_start = bootstrap
    list_end = date.today()
    dates = _date_range(list_start, list_end)
    logger.info(
        f"m=main, env={args.environment}, root={source_root}, "
        f"watermark={watermark}, list_start={list_start}, list_end={list_end}, "
        f"n_days={len(dates)}"
    )

    listed_paths = _list_eval_files(spark, source_root, dates)
    processed_paths = _processed_paths(spark, full_table_name, list_start)
    new_paths = [
        path for path in listed_paths if _strip_scheme(path) not in processed_paths
    ]
    logger.info(
        f"m=main, n_listed={len(listed_paths)}, "
        f"n_processed_in_window={len(processed_paths)}, n_new={len(new_paths)}"
    )

    if new_paths:
        df = _enrich(_read_eval_files(spark, new_paths))
    else:
        df = _empty_enriched_df(spark)

    has_rows = df.limit(1).count() > 0
    table_exists = spark.catalog.tableExists(full_table_name)
    if not has_rows and table_exists:
        logger.info("m=main, msg=No new offline-eval JSON files. Exiting.")
        return
    if not has_rows:
        logger.info(
            "m=main, msg=No offline-eval JSON files in lookback; "
            "bootstrapping empty raw table for sync-metadata."
        )

    metastore_service.create_database(write_database_name)
    raw_path = f"{write_location.rstrip('/')}/{write_table_name}"
    logger.info(f"m=main, table={full_table_name}, path={raw_path}, msg=Merging raw")

    DeltaLoader().load_table(
        table_name=full_table_name,
        path=raw_path,
        source_df=df,
        partition_by=args.partition_cols,
        merge_on=MERGE_ON,
        when_matched_update_condition="FALSE",
    )
    logger.info("m=main, msg=Raw load completed (insert-only merge on s3_path)")


def _strip_scheme(path: str) -> str:
    """Normalize s3:// vs s3a:// so listed and stored paths compare equal."""
    return path.split("://", 1)[-1]


def _date_range(start: date, end: date) -> List[str]:
    if end < start:
        return []
    days = (end - start).days
    return [(start + timedelta(days=i)).strftime(DATE_FMT) for i in range(days + 1)]


def _empty_enriched_df(spark_session: SparkSession) -> DataFrame:
    """Schema-aligned empty frame used to register the raw table on first empty run."""
    return spark_session.createDataFrame(
        [],
        StructType(
            [
                StructField("s3_path", StringType(), True),
                StructField("git_commit", StringType(), True),
                StructField("ts_eval", TimestampType(), True),
                StructField("result_json", StringType(), True),
                StructField("dt_eval", DateType(), True),
                StructField("ts_load", TimestampType(), True),
                StructField("year", IntegerType(), True),
                StructField("month", IntegerType(), True),
                StructField("day", IntegerType(), True),
            ]
        ),
    )


def _watermark_dt_eval(
    spark_session: SparkSession, full_table_name: str
) -> Optional[date]:
    """Latest eval date already in raw (drives the S3 date= listing floor)."""
    if not spark_session.catalog.tableExists(full_table_name):
        logger.info(
            f"m=_watermark_dt_eval, table={full_table_name}, "
            "msg=Raw table missing; bootstrap from load_start_date."
        )
        return None
    row = spark_session.sql(
        f"SELECT max(dt_eval) AS watermark FROM {full_table_name}"
    ).collect()[0]
    watermark = row.watermark
    if watermark is None:
        return None
    if isinstance(watermark, datetime):
        return watermark.date()
    return watermark


def _list_eval_files(
    spark_session: SparkSession, source_root: str, dates: List[str]
) -> List[str]:
    """List eval artifacts only under the given date= prefixes."""
    if not dates:
        return []
    jvm = spark_session.sparkContext._jvm
    hadoop_conf = spark_session.sparkContext._jsc.hadoopConfiguration()
    listed: List[str] = []
    for day in dates:
        glob_uri = f"{source_root}/{DAY_GLOB.format(day=day)}"
        hadoop_path = jvm.org.apache.hadoop.fs.Path(glob_uri)
        fs = hadoop_path.getFileSystem(hadoop_conf)
        statuses = fs.globStatus(hadoop_path)
        if not statuses:
            continue
        listed.extend(status.getPath().toString() for status in statuses)
    return listed


def _processed_paths(
    spark_session: SparkSession, full_table_name: str, list_start: date
) -> Set[str]:
    """s3_path values already in raw for dt_eval >= list_start (partition prune)."""
    if not spark_session.catalog.tableExists(full_table_name):
        return set()
    start = list_start.strftime(DATE_FMT)
    rows = (
        spark_session.table(full_table_name)
        .where(F.col("dt_eval") >= F.lit(start).cast("date"))
        .select("s3_path")
        .collect()
    )
    return {_strip_scheme(row.s3_path) for row in rows}


def _read_eval_files(spark_session: SparkSession, paths: List[str]) -> DataFrame:
    return (
        spark_session.read.format("text")
        .option("wholetext", True)
        .load(paths)
        .selectExpr("_metadata.file_path AS s3_path", "value AS result_json")
    )


def _enrich(df: DataFrame) -> DataFrame:
    """Extract only ops fields from the path; host/suite indexing is clean's job."""
    return (
        df.withColumn(
            "dt_eval", F.to_date(F.regexp_extract("s3_path", PATH_PATTERN, 1))
        )
        .withColumn("git_commit", F.regexp_extract("s3_path", PATH_PATTERN, 2))
        .withColumn(
            "ts_eval",
            F.to_timestamp(
                F.regexp_extract("s3_path", PATH_PATTERN, 3), TS_EVAL_FORMAT
            ),
        )
        .withColumn("ts_load", F.current_timestamp())
        .withColumn("year", F.year("dt_eval"))
        .withColumn("month", F.month("dt_eval"))
        .withColumn("day", F.dayofmonth("dt_eval"))
        .filter(F.col("dt_eval").isNotNull())
        .filter(F.col("git_commit") != "")
        .filter(F.col("ts_eval").isNotNull())
        .select(
            "s3_path",
            "git_commit",
            "ts_eval",
            "result_json",
            "dt_eval",
            "ts_load",
            "year",
            "month",
            "day",
        )
    )


if __name__ == "__main__":
    main()
