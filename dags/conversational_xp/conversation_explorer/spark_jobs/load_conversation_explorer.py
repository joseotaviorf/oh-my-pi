import json
import logging
import re
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat, SparkDataFrameService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_conversation_explorer"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

SOURCE_BUCKET_PROD = "s3://conversation-explorer-prod/session-metadata"

DATE_PATTERN = re.compile(r"(\d{4}-\d{2}-\d{2})\.parquet$")


def _get_source_base_path(environment: str) -> str:
    if environment != "prod":
        raise ValueError(
            f"This job only runs in prod (source bucket is prod-only). Got environment='{environment}'"
        )
    return SOURCE_BUCKET_PROD


def _find_most_recent_file(spark_client: SparkClient, base_path: str) -> str:
    """List parquet files in the S3 directory and return the one uploaded most recently (by S3 last-modified)."""
    hadoop_conf = spark_client.conn.sparkContext._jsc.hadoopConfiguration()
    fs_uri = spark_client.conn._jvm.java.net.URI(base_path)
    fs = spark_client.conn._jvm.org.apache.hadoop.fs.FileSystem.get(fs_uri, hadoop_conf)
    path = spark_client.conn._jvm.org.apache.hadoop.fs.Path(base_path)

    files = fs.listStatus(path)
    candidates = []
    for file_status in files:
        filename = file_status.getPath().getName()
        if DATE_PATTERN.match(filename):
            candidates.append((file_status.getModificationTime(), filename))

    if not candidates:
        raise FileNotFoundError(f"No YYYY-MM-DD.parquet files found in {base_path}")

    candidates.sort(key=lambda x: x[0], reverse=True)
    most_recent_filename = candidates[0][1]
    logger.info(f"m=_find_most_recent_file, msg=Found {len(candidates)} files, most recently uploaded: {most_recent_filename}")
    return f"{base_path}/{most_recent_filename}"


def main() -> None:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("bucket", help="datalake bucket")
    parser.add_argument("source", help="schema name used for metastore resolution")
    parser.add_argument("table_name", help="name of the output table")
    parser.add_argument("partitions", help="JSON list of partition columns")
    parser.add_argument("date", nargs="?", default="", help="Optional YYYY-MM-DD to load a specific file (for backfills)")

    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.bucket
    source = args.source
    table_name = args.table_name
    partition_cols = json.loads(args.partitions.replace("'", '"'))
    file_date = args.date.strip() if args.date else ""

    logger.info(
        f"m=__main__, environment={environment}, source={source}, "
        f"table_name={table_name}, file_date={file_date or '(auto-detect most recent)'}, "
        f"msg=Starting spark job..."
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    s3_loader = S3Loader()

    base_path = _get_source_base_path(environment)
    if file_date:
        source_path = f"{base_path}/{file_date}.parquet"
        logger.info(f"m=__main__, msg=Using explicit file_date: {source_path}")
    else:
        source_path = _find_most_recent_file(spark_client, base_path)
        logger.info(f"m=__main__, msg=Most recent file found: {source_path}")

    db_info = DatalakeMetastoreService.get_db_info(
        env=environment, source=source, bucket=datalake_bucket
    )
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    df = s3_consumer.get_data_from_file(path=source_path, format="parquet")

    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column("session_date")
        .output()
    )

    logger.info(
        f"m=__main__, msg=Loaded {df.count()} rows, writing to {database_name}.{table_name}"
    )

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=SparkTableStorageFormat.PARQUET,
        partitions=partition_cols,
    )

    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=SparkTableStorageFormat.PARQUET,
        database_location=database_location,
        partitions=partition_cols,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=database_name,
        table_name=table_name,
        partition_cols=partition_cols,
    )

    logger.info(f"m=__main__, msg=Job completed successfully")


if __name__ == "__main__":
    main()
