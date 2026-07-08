import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta
from functools import reduce
from typing import List

from pyspark.sql import functions as F
from pyspark.sql.types import LongType
from pyspark.sql.window import Window
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

JOB_NAME = "load_vocs_machina_raw"

DATE_FMT = "%Y-%m-%d"

# vocs-machina finalizes a complete partition as part-0000.parquet plus a
# _SUCCESS marker, deleting the partial-<run_id>-*.parquet checkpoints it wrote
# while classification was in flight. In-progress or crashed partitions leave
# those partial files behind with NO _SUCCESS. We must ingest only finalized
# output, so we restrict the read to the canonical file name. The glob
# "part-*.parquet" matches part-0000.parquet but never "partial-*.parquet"
# (the character after "part" is a literal "-", absent in "partial").
FINALIZED_PARQUET_GLOB = "part-*.parquet"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

# Business columns read from each vocs-machina ClassificationRow parquet.
# ts_load is added here; year/month/day are derived from the load date in
# _prepare_day_df (NOT taken from the parquet) so rows always land in the
# Hive partition for the day being ingested.
PERSISTED_COLUMNS = [
    "feedback_id",
    "prompt_id",
    "prompt_hash",
    "label",
    "reasoning",
    "verbatim_text",
    "feedback_kind",
    "source_name",
    "rating",
    "submitted_at",
    "customer_type",
    "author_id",
    "account_id",
    "campaign_name",
    "llm_model",
    "llm_temperature",
    "prompt_collection",
    "prompt_opportunity",
    "ts_classified",
    "run_id",
]

# Columns the upstream vocs-machina writer emits as pandas datetime64[ns], i.e.
# Parquet INT64 (TIMESTAMP(NANOS,true)). With spark.sql.legacy.parquet.nanosAsLong
# these arrive as LongType (nanos since epoch) and must be cast back to
# TimestampType so the raw table keeps the schema the clean SQL expects.
NANOS_TIMESTAMP_COLUMNS = ("submitted_at", "ts_classified")


def get_forno_adjusted_data_science_path(
    environment: str, source_root_path: str
) -> str:
    """Resolve data-science bucket host for forno vs prod/staging."""
    if environment == "forno":
        return source_root_path.replace(
            "s3://data-science.s3.data", "s3://data-science.s3.forno.data"
        )
    return source_root_path


def build_day_partition_uri(source_root_path: str, date_str: str) -> str:
    """Build S3 URI for one day's partition directory (all prompt_id/prompt_hash subdirs)."""
    dt = datetime.strptime(date_str, DATE_FMT)
    base = source_root_path.rstrip("/")
    return f"{base}/raw/year={dt.year}/month={dt.month:02d}/day={dt.day:02d}"


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


def _cast_nanos_timestamps(df):
    # With spark.sql.legacy.parquet.nanosAsLong=true, Parquet INT64
    # (TIMESTAMP(NANOS,isAdjustedToUTC=true)) columns are read as LongType
    # (nanoseconds since epoch UTC). Restore TimestampType so the raw table
    # keeps the schema the clean SQL expects.
    #
    # Convert nanos -> micros with integer division, then timestamp_micros.
    # A float path (col / 1e9 + timestamp_seconds) is NOT safe here: the
    # nanosecond magnitude is ~1.75e18, far beyond the 2^53 exact-integer
    # range of a double, so casting the long to double drops sub-microsecond
    # bits and can shift the value by ~1 us. Integer `div` keeps microsecond
    # precision exactly (Spark timestamps are microsecond-precision anyway).
    #
    # The isinstance(LongType) guard makes this a no-op if a partition was
    # written with MICROS/MILLIS (older producer), where Spark already yields
    # TimestampType.
    for col_name in NANOS_TIMESTAMP_COLUMNS:
        if col_name in df.columns and isinstance(
            df.schema[col_name].dataType, LongType
        ):
            # `div` is Spark SQL integer division on bigints (exact, no float
            # coercion); timestamp_micros then reads micros-since-epoch as UTC.
            df = df.withColumn(
                col_name,
                F.expr(f"timestamp_micros(`{col_name}` div 1000)"),
            )
    return df


def _prepare_day_df(df, date_str):
    missing_cols = [c for c in PERSISTED_COLUMNS if c not in df.columns]
    if missing_cols:
        raise ValueError(
            f"m=load_day, date={date_str}, msg=Parquet schema missing expected columns: "
            f"{missing_cols}"
        )
    dt_execution = datetime.strptime(date_str, DATE_FMT)
    out = df.select(*PERSISTED_COLUMNS)
    out = _cast_nanos_timestamps(out)
    # Instrumentation (debug session 7256d1): confirm the cast produced
    # TimestampType with sane values.
    logger.info(
        f"m=load_day, date={date_str}, "
        f"msg=timestamp types after cast, "
        f"ts_types={ {c: str(out.schema[c].dataType) for c in NANOS_TIMESTAMP_COLUMNS} }"
    )
    out = out.withColumn("ts_load", F.current_timestamp())
    # year/month/day are derived from the load date rather than read from the
    # parquet, so rows always land in the partition for the day being ingested.
    out = (
        out.withColumn("year", F.lit(dt_execution.year))
        .withColumn("month", F.lit(dt_execution.month))
        .withColumn("day", F.lit(dt_execution.day))
    )
    return out


def _dedup_df(df):
    # vocs-machina can classify the same feedback twice in the same run due to a
    # race condition in its parallel worker pool (ts_classified differs by ~1-4s,
    # same run_id). Without deduplication, Delta MERGE raises
    # DeltaUnsupportedOperationException when the target row already exists and
    # two source rows match the same merge key. Keep latest ts_classified.
    _dedup_window = Window.partitionBy(
        "feedback_id", "prompt_id", "prompt_hash", "year", "month", "day"
    ).orderBy(F.col("ts_classified").desc())
    return (
        df.withColumn("_row_num", F.row_number().over(_dedup_window))
        .filter(F.col("_row_num") == 1)
        .drop("_row_num")
    )


def main() -> None:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod/staging values")
    parser.add_argument("bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source (dag name)")
    parser.add_argument(
        "source_root_path",
        help="S3 base path for vocs-machina output (no trailing slash)",
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

    add_validation_target_args(parser)
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
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=args.bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )
    format_options = SparkTableStorageFormat.PARQUET

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=main, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(write_database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    dfs = []
    for date_str in calendar_days:
        day_uri = build_day_partition_uri(source_root_path, date_str)
        try:
            # recursiveFileLookup disables Hive partition inference: the day URI
            # sits above prompt_id=/prompt_hash= dirs that also exist as physical
            # columns, and inference would raise a duplicate-column error. All
            # columns are read straight from the parquet files instead.
            # pathGlobFilter restricts the read to finalized part-*.parquet so we
            # never ingest partial-*.parquet checkpoints from an incomplete
            # partition (which would land subset/duplicate rows and can break the
            # downstream MERGE on duplicated merge keys).
            raw_df = s3_consumer.get_data_from_file(
                day_uri,
                data_format,
                {
                    "recursiveFileLookup": "true",
                    "pathGlobFilter": FINALIZED_PARQUET_GLOB,
                },
            )

            # Instrumentation (debug session 7256d1): surface the inferred
            # Spark types of the timestamp columns so the post-fix task log
            # confirms which columns arrived as LongType (nanos) and that the
            # cast produced sane TimestampType values.
            ts_types = {
                c: str(raw_df.schema[c].dataType)
                for c in NANOS_TIMESTAMP_COLUMNS
                if c in raw_df.columns
            }
            logger.info(
                f"m=load_day, date={date_str}, uri={day_uri}, "
                f"msg=inferred timestamp types after read, ts_types={ts_types}"
            )
            probe_cols = [c for c in NANOS_TIMESTAMP_COLUMNS if c in raw_df.columns]
            if probe_cols:
                probe = raw_df.select(*probe_cols).limit(3).collect()
                logger.info(
                    f"m=load_day, date={date_str}, "
                    f"msg=sample values after read (pre-cast), "
                    f"samples={[r.asDict() for r in probe]}"
                )
        except Exception as exc:
            msg = str(exc)
            if "Path does not exist" in msg or "PATH_NOT_FOUND" in msg:
                logger.warning(
                    f"m=main, msg=No partition for date (expected on no-data days). "
                    f"uri={day_uri}"
                )
                continue
            # Any other failure (auth, corruption, schema) is a real error: do
            # not swallow it as "no data" — that would silently write nothing.
            raise

        day_df = _prepare_day_df(raw_df, date_str)

        if day_df.rdd.isEmpty():
            logger.warning(
                f"m=main, msg=Parquet for {date_str} is empty; skipping that day."
            )
            continue
        dfs.append(day_df)

    if not dfs:
        table_exists = spark_client.conn.catalog.tableExists(
            f"{write_database_name}.{write_table_name}"
        )
        if not table_exists:
            first_uri = build_day_partition_uri(source_root_path, load_start_date)
            raise RuntimeError(
                f"m=main, msg=No S3 data found for range "
                f"{load_start_date}..{load_end_date} and table "
                f"{write_database_name}.{write_table_name} does not yet exist. "
                f"Bootstrap the table by triggering a manual backfill for a date "
                f"that already has vocs-machina output in S3 "
                f"(expected URI pattern: {first_uri}). "
                f"The dataset-driven schedule only fires after vocs-machina emits "
                f"quintoml.post_contract.vocs_machina.inference; manual runs must "
                f"supply a load_start_date / load_end_date in the DAG conf JSON."
            )
        logger.warning(
            f"m=main, msg=No data loaded for any day in range "
            f"{load_start_date}..{load_end_date}; table already initialised, "
            f"skipping S3 write and metastore update."
        )
        return

    df_out = reduce(lambda a, b: a.unionByName(b), dfs)
    df_out = _dedup_df(df_out)

    s3_loader.load_df(
        df=df_out,
        s3_path=f"{write_location}{write_table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )

    spark_metastore_loader.update_metastore(
        df=df_out,
        database_name=write_database_name,
        table_name=write_table_name,
        format_options=format_options,
        database_location=write_location,
        partitions=partition_cols,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df_out,
        database_name=write_database_name,
        table_name=write_table_name,
        partition_cols=partition_cols,
    )

    logger.info(
        f"m=main, msg=Successfully loaded {table_name} "
        f"({len(dfs)} day(s)) into datalake"
    )


if __name__ == "__main__":
    main()
