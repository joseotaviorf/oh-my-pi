import json
import logging
from argparse import ArgumentParser
from datetime import datetime

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
        "date_to_ingest",
        help="Calendar date for the file to load. Format: YYYY-mm-dd",
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
    date_to_ingest = args.date_to_ingest
    table_name = args.table_name
    partition_cols = json.loads(args.partitions.replace("'", '"'))
    data_format = args.format

    parquet_uri = build_session_metadata_parquet_uri(source_root_path, date_to_ingest)

    logger.info(
        f"m=main, environment={environment}, source={source}, parquet_uri={parquet_uri}, "
        f"date_to_ingest={date_to_ingest}, table_name={table_name}, msg=Starting spark job..."
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

    dt_execution = datetime.strptime(date_to_ingest, "%Y-%m-%d")

    try:
        df = s3_consumer.get_data_from_file(parquet_uri, data_format)
    except Exception as exc:
        logger.warning(
            f"m=main, msg=No parquet loaded for date (missing or unreadable file). "
            f"uri={parquet_uri}, exception={exc}"
        )
        return

    missing_cols = [c for c in PERSISTED_COLUMNS if c not in df.columns]
    if missing_cols:
        raise ValueError(
            f"m=main, msg=Parquet schema missing expected columns: {missing_cols}"
        )

    df = df.select(*PERSISTED_COLUMNS)
    df = df.withColumn("ts_load", F.current_timestamp())

    df = (
        df.withColumn("year", F.lit(dt_execution.year))
        .withColumn("month", F.lit(dt_execution.month))
        .withColumn("day", F.lit(dt_execution.day))
    )

    if df.rdd.isEmpty():
        logger.warning(
            f"m=main, msg=Parquet for {date_to_ingest} is empty; skipping load and metastore update."
        )
        return

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )

    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
        partitions=partition_cols,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=database_name,
        table_name=table_name,
        partition_cols=partition_cols,
    )

    logger.info(f"m=main, msg=Successfully loaded {table_name} into datalake")


if __name__ == "__main__":
    main()
