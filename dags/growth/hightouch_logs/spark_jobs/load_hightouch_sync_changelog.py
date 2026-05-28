from argparse import ArgumentParser
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from time import monotonic
from typing import Optional

import pyspark.sql.functions as F
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "Hightouch Sync Changelog Trino Load"
RAW_PARTITION_COLUMNS = ["year", "month", "day"]
logger = QuintoAndarLogger(JOB_NAME)


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
    """Returns paths under sync_run_path modified in [start_ts, end_ts)."""
    return [
        file.path
        for file in dbutils.fs.ls(sync_run_path)
        if start_ts <= file.modificationTime < end_ts
    ]


def _fetch_filtered_paths(paths: list[str], is_backfill: str) -> list[str]:
    if is_backfill == "true":
        return paths
    return sorted(
        paths,
        key=lambda path: int(path.rstrip("/").split("sync_run_id=")[-1]),
        reverse=True,
    )[:720]


def _discover_parquet_paths(
    base_path: str, is_backfill: str, load_start_date: str, load_end_date: str
) -> list[str]:
    """Lists sync_id/sync_run_id partitions and collects paths by modification time.

    Each sync_id directory is listed in parallel to minimise wall-clock time on
    the I/O-bound dbutils.fs.ls calls.
    """
    start_ts, end_ts = _load_window_timestamps_ms(load_start_date, load_end_date)

    t0 = monotonic()
    sync_dirs = [
        sync_dir.path
        for sync_dir in dbutils.fs.ls(base_path)
        if sync_dir.name.startswith("sync_id=")
    ]
    sync_dirs_elapsed = monotonic() - t0
    logger.info(
        f"m=_discover_parquet_paths, sync_dir_count={len(sync_dirs)}, "
        f"elapsed_s={sync_dirs_elapsed:.2f}, msg=listed sync_id directories"
    )

    if not sync_dirs:
        logger.info(
            f"m=_discover_parquet_paths, base_path={base_path}, "
            "msg=no sync_id directories found, returning empty path list"
        )
        return []

    def _list_sync_dir(sync_path: str) -> list[str]:
        return _fetch_filtered_paths(
            _fetch_parquet_paths_modified_in_window(sync_path, start_ts, end_ts),
            is_backfill,
        )

    t1 = monotonic()
    with ThreadPoolExecutor(max_workers=min(len(sync_dirs), 16)) as executor:
        results = list(executor.map(_list_sync_dir, sync_dirs))
    sync_runs_elapsed = monotonic() - t1

    paths = [path for sublist in results for path in sublist]

    logger.info(
        f"m=_discover_parquet_paths, sync_dir_count={len(sync_dirs)}, "
        f"parquet_file_count={len(paths)}, elapsed_s={sync_runs_elapsed:.2f}, "
        "msg=listed sync_run_id directories in parallel"
    )
    return paths


def _add_partitions_from_load_date(df: DataFrame, load_start_date: str) -> DataFrame:
    """Adds year/month/day partition columns derived from the load window start date."""
    dt = datetime.strptime(load_start_date, "%Y-%m-%d")
    return (
        df.withColumn("year", F.lit(dt.year))
        .withColumn("month", F.lit(dt.month))
        .withColumn("day", F.lit(dt.day))
    )


def _read_sync_changelog_input(
    spark: SparkSession,
    base_path: str,
    is_backfill: str,
    load_start_date: str,
    load_end_date: str,
) -> Optional[DataFrame]:
    """Reads sync_changelog parquet files from S3 filtered by modification time."""
    paths = _discover_parquet_paths(
        base_path, is_backfill, load_start_date, load_end_date
    )
    if not paths:
        logger.info(
            f"m=_read_sync_changelog_input, base_path={base_path}, "
            f"load_start_date={load_start_date}, load_end_date={load_end_date}, "
            "msg=no changelog files modified in range"
        )
        return None

    try:
        df = (
            spark.read.option("ignoreMissingFiles", "true")
            .option("basePath", base_path)
            .parquet(*paths)
        )
    except AnalysisException as exc:
        logger.info(f"m=_read_sync_changelog_input, msg=failed to read parquet: {exc}")
        return None

    return _add_partitions_from_load_date(df, load_start_date)


def _write_to_raw(
    df: DataFrame,
    environment: str,
    source: str,
    datalake_bucket: str,
    table_name: str,
) -> None:
    spark_client = SparkClient()

    if UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        current_catalog = UnityCatalogHelper.get_current_catalog()
        spark_client.conn.sql(f"USE CATALOG {current_catalog}")

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    full_table_path = f"{database_location}{table_name}"

    SparkMetastoreService(spark_client).create_database(database_name)

    S3Loader().load_df(
        df=df,
        s3_path=full_table_path,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        partitions=RAW_PARTITION_COLUMNS,
        optimize_dataframe=False,
    )


class HightouchSyncChangelogSparkJob(BaseCoreModelSparkJob):
    """Ingests Hightouch reverse ETL sync_changelog parquet data from S3 into the raw Delta layer."""

    def __init__(self):
        super().__init__(JOB_NAME)

    def parse_args(self):
        """Parse arguments matching the declaration's extra_spark_job_arguments order."""
        parser = ArgumentParser(description=self.job_name)
        parser.add_argument("environment", help="Target environment")
        parser.add_argument("datalake_bucket", help="Data lake S3 bucket")
        parser.add_argument("schema", help="Database schema name")
        parser.add_argument("dag_name", help="DAG / source name")
        parser.add_argument("table_name", help="Table name")
        parser.add_argument("is_backfill", help="Backfill toggle (true/false)")
        parser.add_argument(
            "load_start_date", help="Load window start date (YYYY-MM-DD)"
        )
        parser.add_argument("load_end_date", help="Load window end date (YYYY-MM-DD)")
        parser.add_argument("extraction_type", help="Extraction type")
        parser.add_argument(
            "incremental_column",
            help="Incremental column (unused, kept for interface parity)",
        )
        parser.add_argument(
            "input_path", help="S3 path to Hightouch sync_changelog parquet data"
        )
        parser.add_argument(
            "format", help="Input format (unused, kept for interface parity)"
        )
        return parser.parse_args()

    def create_sync_changelog_df(
        self, spark: SparkSession, args
    ) -> Optional[DataFrame]:
        """Discover, read, and partition-annotate sync_changelog parquet from S3."""
        input_path = args.input_path.format(environment=args.environment)
        return _read_sync_changelog_input(
            spark=spark,
            base_path=input_path,
            is_backfill=args.is_backfill,
            load_start_date=args.load_start_date,
            load_end_date=args.load_end_date,
        )

    def run_pipeline(self, df: DataFrame, args, spark: SparkSession) -> None:
        """Write the DataFrame to the raw layer using S3Loader."""
        _write_to_raw(
            df=df,
            environment=args.environment,
            source=args.dag_name,
            datalake_bucket=args.datalake_bucket,
            table_name=args.table_name,
        )

    def run(self) -> None:
        """Main execution entry point."""
        args = self.parse_args()
        self.initialize_configuration(args.dag_name)

        input_path = args.input_path.format(environment=args.environment)
        self.logger.info(
            f"m=run, environment={args.environment}, datalake_bucket={args.datalake_bucket}, "
            f"dag_name={args.dag_name}, table_name={args.table_name}, "
            f"is_backfill={args.is_backfill}, load_start_date={args.load_start_date}, "
            f"load_end_date={args.load_end_date}, input_path={input_path}, "
            "msg=starting spark job"
        )

        spark = self.initialize_spark_session()

        df = self.create_sync_changelog_df(spark, args)
        if df is None:
            self.logger.info(
                "m=run, msg=no sync_changelog data in range, skipping write"
            )
            return

        self.run_pipeline(df, args, spark)
        self.logger.info("m=run, msg=spark job finished")


if __name__ == "__main__":
    HightouchSyncChangelogSparkJob().run()
