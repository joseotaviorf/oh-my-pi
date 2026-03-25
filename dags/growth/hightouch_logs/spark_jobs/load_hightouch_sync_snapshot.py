from argparse import ArgumentParser
from datetime import datetime, timedelta
from functools import reduce
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


def _read_snapshot_input(
    base_path: str, load_start_date: str, load_end_date: str
) -> Optional[DataFrame]:
    """Reads parquet per YYYYMMDD path segment and adds year, month, day from that calendar day."""
    start = datetime.strptime(load_start_date, "%Y-%m-%d")
    end = datetime.strptime(load_end_date, "%Y-%m-%d")

    dfs = []
    current = start
    while current <= end:
        date_str = current.strftime("%Y%m%d")
        path_glob = f"{base_path}/sync_id=*/{date_str}*"
        try:
            day_df = spark.read.parquet(path_glob)
        except AnalysisException as exc:
            logger.info(
                "m=_read_snapshot_input, path_glob={}, msg=skipping day (no parquet): {}".format(
                    path_glob, exc
                )
            )
            current += timedelta(days=1)
            continue

        day_df = (
            day_df.withColumn("year", F.lit(current.year))
            .withColumn("month", F.lit(current.month))
            .withColumn("day", F.lit(current.day))
        )
        dfs.append(day_df)
        current += timedelta(days=1)

    if not dfs:
        logger.info(
            "m=_read_snapshot_input, load_start_date={}, load_end_date={}, msg=no parquet in range, nothing to load".format(
                load_start_date, load_end_date
            )
        )
        return None

    return reduce(lambda a, b: a.unionByName(b), dfs)


def _write_to_raw(df, environment: str, source: str, datalake_bucket: str, table_name: str):
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
        "m=main, environment={}, datalake_bucket={}, source={}, table_name={}, "
        "load_start_date={}, load_end_date={}, input_path={}, msg=starting spark job".format(
            args.environment,
            args.datalake_bucket,
            args.source,
            args.table_name,
            args.load_start_date,
            args.load_end_date,
            input_path,
        )
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

    logger.info("m=main, row_count={}, msg=spark job finished".format(df.count()))


if __name__ == "__main__":
    main()
