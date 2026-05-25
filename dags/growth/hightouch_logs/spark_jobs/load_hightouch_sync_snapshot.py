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

JOB_NAME = "Hightouch Sync Snapshot Load"
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
    sync_snapshot_path: str, start_ts: int, end_ts: int
) -> list[str]:
    """Returns parquet file paths under sync_snapshot_path modified in [start_ts, end_ts)."""
    return [
        file.path
        for file in dbutils.fs.ls(sync_snapshot_path)
        if start_ts <= file.modificationTime < end_ts
    ]


def _discover_snapshot_paths(
    base_path: str,
    load_start_date: str,
    load_end_date: str,
) -> list[str]:
    """Lists sync_id partitions and collects snapshot parquet paths by modification time."""
    start_ts, end_ts = _load_window_timestamps_ms(load_start_date, load_end_date)

    sync_dirs = [
        sync_dir.path
        for sync_dir in dbutils.fs.ls(base_path)
        if sync_dir.name.startswith("sync_id=")
    ]

    paths: list[str] = []
    for sync_path in sync_dirs:
        paths.extend(
            _fetch_parquet_paths_modified_in_window(sync_path, start_ts, end_ts)
        )

    logger.info(
        f"m=_discover_snapshot_paths, sync_dir_count={len(sync_dirs)}, parquet_file_count={len(paths)}, "
        f"load_start_date={load_start_date}, load_end_date={load_end_date}, msg=discovered source files"
    )
    return paths


def _add_partitions_from_file_path(df: DataFrame) -> DataFrame:
    """Derives year, month, day from the YYYYMMDD segment in the snapshot file path."""
    return (
        df.withColumn("_file_path", F.input_file_name())
        .withColumn("snapshot_date", F.regexp_extract("_file_path", r"(\d{8})", 1))
        .withColumn("year", F.substring("snapshot_date", 1, 4).cast("int"))
        .withColumn("month", F.substring("snapshot_date", 5, 2).cast("int"))
        .withColumn("day", F.substring("snapshot_date", 7, 2).cast("int"))
        .drop("_file_path", "snapshot_date")
    )


def _read_snapshot_input(
    base_path: str, load_start_date: str, load_end_date: str
) -> Optional[DataFrame]:
    """Reads snapshot parquet files discovered by modification time.

    Raw partitions (year, month, day) are derived from the YYYYMMDD segment in each
    file path. sync_id is recovered via basePath partition discovery.
    """
    paths = _discover_snapshot_paths(base_path, load_start_date, load_end_date)
    if not paths:
        logger.info(
            f"m=_read_snapshot_input, base_path={base_path}, load_start_date={load_start_date}, load_end_date={load_end_date}, "
            "msg=no parquet files modified in range"
        )
        return None

    logger.info(
        f"m=_read_snapshot_input, path_count={len(paths)}, msg=reading parquet files"
    )
    try:
        df = (
            spark.read.option("ignoreMissingFiles", "true")
            .option("basePath", base_path)
            .parquet(*paths)
        )
    except AnalysisException as exc:
        logger.info(f"m=_read_snapshot_input, msg=failed to read parquet: {exc}")
        return None

    return _add_partitions_from_file_path(df)


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
    parser.add_argument("load_start_date", help="Load start date")
    parser.add_argument("load_end_date", help="Load end date")
    parser.add_argument("extraction_type", help="Extraction type")
    parser.add_argument("incremental_column", help="Incremental column")
    parser.add_argument("input_path", help="Input path")
    parser.add_argument("format", help="Input format")
    return parser.parse_args()


def main():
    args = parse_arguments()
    input_path = args.input_path.format(environment=args.environment)

    logger.info(
        f"m=main, environment={args.environment}, datalake_bucket={args.datalake_bucket}, source={args.source}, table_name={args.table_name}, "
        f"load_start_date={args.load_start_date}, load_end_date={args.load_end_date}, input_path={input_path}, msg=starting spark job"
    )

    df = _read_snapshot_input(
        base_path=input_path,
        load_start_date=args.load_start_date,
        load_end_date=args.load_end_date,
    )
    if df is None:
        logger.info("m=main, msg=no snapshot data in range, skipping write")
        return

    _write_to_raw(
        df=df,
        environment=args.environment,
        source=args.source,
        datalake_bucket=args.datalake_bucket,
        table_name=args.table_name,
    )

    logger.info(f"m=main, row_count={df.count()}, msg=spark job finished")


if __name__ == "__main__":
    main()
