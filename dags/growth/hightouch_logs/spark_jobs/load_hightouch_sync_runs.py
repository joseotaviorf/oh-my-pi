from argparse import ArgumentParser
from datetime import datetime, timedelta
from typing import Optional

import pyspark.sql.functions as F
from pyspark.sql import DataFrame
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "Hightouch Sync Runs Trino Load"
RAW_PARTITION_COLUMNS = ["year", "month", "day"]
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient()
spark = spark_client.conn


def _load_window_timestamps_ms(
    load_start_date: str, load_end_date: str
) -> tuple[int, int]:
    start_ts = int(datetime.strptime(load_start_date, "%Y-%m-%d").timestamp() * 1000)
    end_ts = int(
        (datetime.strptime(load_end_date, "%Y-%m-%d") + timedelta(days=1)).timestamp()
        * 1000
    )
    return start_ts, end_ts


def _fetch_parquet_paths_modified_in_window(
    sync_run_path: str, start_ts: int, end_ts: int
) -> list[str]:
    """Returns parquet file paths under sync_run_path modified in [start_ts, end_ts)."""
    return [
        file.path
        for file in dbutils.fs.ls(sync_run_path)
        if start_ts <= file.modificationTime < end_ts
    ]


def _fetch_filtered_paths(paths: list, is_backfill: str) -> list[str]:
    """
    Returns filtered parquet file paths based on backfill flag.
    If backfill flag is true, returns all paths.
    Otherwise, returns the latest 100 paths.
    """
    if is_backfill == "true":
        return paths
    else:
        sorted_paths = sorted(
            paths,
            key=lambda path: int(path.rstrip("/").split("sync_run_id=")[-1]),
            reverse=True,
        )[:720]
        return sorted_paths


def _discover_parquet_paths(
    base_path: str, is_backfill: str, load_start_date: str, load_end_date: str
) -> list[str]:
    """Lists sync_id/sync_run_id partitions and collects parquet paths by modification time."""
    start_ts, end_ts = _load_window_timestamps_ms(load_start_date, load_end_date)

    sync_dirs = [
        sync_dir.path
        for sync_dir in dbutils.fs.ls(base_path)
        if sync_dir.name.startswith("sync_id=")
    ]

    sync_runs_paths = [
        _fetch_filtered_paths(run_dir, is_backfill)
        for run_dir in [
            _fetch_parquet_paths_modified_in_window(sync_path, start_ts, end_ts)
            for sync_path in sync_dirs
        ]
    ]

    paths = [path for path in sync_runs_paths for path in path]

    logger.info(
        f"m=_discover_parquet_paths, sync_dir_count={len(sync_dirs)}"
        f"parquet_file_count={len(paths)}, msg=discovered source files"
    )
    return paths


def _filter_incremental_window(
    df: DataFrame,
    load_start_date: str,
    load_end_date: str,
    incremental_column: str,
) -> DataFrame:
    incremental_col = F.col(incremental_column)
    return df.filter(
        (incremental_col.cast("date") >= F.to_date(F.lit(load_start_date)))
        & (incremental_col.cast("date") <= F.to_date(F.lit(load_end_date)))
    )


def _add_partitions_from_incremental_column(
    df: DataFrame, incremental_column: str
) -> DataFrame:
    incremental_col = F.col(incremental_column).cast("timestamp")
    return (
        df.withColumn("year", F.year(incremental_col))
        .withColumn("month", F.month(incremental_col))
        .withColumn("day", F.dayofmonth(incremental_col))
    )


def _read_sync_runs_input(
    base_path: str,
    is_backfill: str,
    load_start_date: str,
    load_end_date: str,
    incremental_column: str,
) -> Optional[DataFrame]:
    """Reads parquet files from sync_id/sync_run_id partitions filtered by modification time.

    Raw partitions (year, month, day) are derived from the incremental column.
    """
    paths = _discover_parquet_paths(
        base_path, is_backfill, load_start_date, load_end_date
    )
    if not paths:
        logger.info(
            f"m=_read_sync_runs_input, base_path={base_path}, is_backfill={is_backfill}, load_start_date={load_start_date}, load_end_date={load_end_date}, "
            "msg=no parquet files modified in range"
        )
        return None

    logger.info(
        f"m=_read_sync_runs_input, path_count={len(paths)}, msg=reading parquet files"
    )
    try:
        df = (
            spark.read.option("ignoreMissingFiles", "true")
            .option("basePath", base_path)
            .parquet(*paths)
        )
    except AnalysisException as exc:
        logger.info(f"m=_read_sync_runs_input, msg=failed to read parquet: {exc}")
        return None

    df = _filter_incremental_window(
        df, load_start_date, load_end_date, incremental_column
    )
    return _add_partitions_from_incremental_column(df, incremental_column)


def _write_to_raw(
    df, environment: str, source: str, datalake_bucket: str, table_name: str
):
    if UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        current_catalog = UnityCatalogHelper.get_current_catalog()
        spark.sql(f"USE CATALOG {current_catalog}")

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    full_table_path = f"{database_location}{table_name}"

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    s3_loader.load_df(
        df=df,
        s3_path=full_table_path,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        partitions=RAW_PARTITION_COLUMNS,
        optimize_dataframe=False,
    )


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="Target environment")
    parser.add_argument("datalake_bucket", help="Data lake S3 bucket")
    parser.add_argument("schema", help="Database schema name")
    parser.add_argument("source", help="Source name")
    parser.add_argument("table_name", help="Table name")
    parser.add_argument("is_backfill", help="Is backfill string toggle")
    parser.add_argument("load_start_date", help="Load start date")
    parser.add_argument("load_end_date", help="Load end date")
    parser.add_argument("extraction_type", help="Extraction type")
    parser.add_argument("incremental_column", help="Incremental column")
    parser.add_argument("input_path", help="Input path")
    parser.add_argument(
        "format", help="Input format (unused, kept for interface parity)"
    )
    return parser.parse_args()


def main():
    args = parse_arguments()
    input_path = args.input_path.format(environment=args.environment)

    logger.info(
        f"m=main, environment={args.environment}, datalake_bucket={args.datalake_bucket}, source={args.source}, table_name={args.table_name}, is_backfill={args.is_backfill}, "
        f"load_start_date={args.load_start_date}, load_end_date={args.load_end_date}, incremental_column={args.incremental_column}, input_path={input_path}, "
        "msg=starting spark job"
    )

    df = _read_sync_runs_input(
        base_path=input_path,
        is_backfill=args.is_backfill,
        load_start_date=args.load_start_date,
        load_end_date=args.load_end_date,
        incremental_column=args.incremental_column,
    )
    if df is None:
        logger.info("m=main, msg=no sync_runs data in range, skipping write")
    elif df.count() == 0:
        logger.info("m=main, msg=no sync_runs data in range, skipping write")
    else:
        _write_to_raw(
            df=df,
            environment=args.environment,
            source=args.source,
            datalake_bucket=args.datalake_bucket,
            table_name=args.table_name,
        )

        logger.info("m=main, msg=spark job finished")


if __name__ == "__main__":
    main()
