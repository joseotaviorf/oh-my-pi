import json
import logging
import re
from argparse import ArgumentParser

from pyspark.sql import functions as F
from pyspark.sql.types import StringType, StructField, StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkDataFrameService, SparkTableStorageFormat
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_conversation_explorer"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

SOURCE_BUCKET = "s3://conversation-explorer-prod"
SOURCE_SESSION_METADATA_PATH = f"{SOURCE_BUCKET}/session-metadata"
SOURCE_ANNOTATIONS_INDEX_PATH = f"{SOURCE_BUCKET}/annotations-index"

DATE_PATTERN = re.compile(r"(\d{4}-\d{2}-\d{2})\.parquet$")
DATE_FOLDER_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _get_source_base_path(environment: str) -> str:
    if environment != "prod":
        raise ValueError(
            f"This job only runs in prod (source bucket is prod-only). Got environment='{environment}'"
        )
    return SOURCE_SESSION_METADATA_PATH


def _get_hadoop_fs(spark_client: SparkClient, base_path: str):
    hadoop_conf = spark_client.conn.sparkContext._jsc.hadoopConfiguration()
    fs_uri = spark_client.conn._jvm.java.net.URI(base_path)
    fs = spark_client.conn._jvm.org.apache.hadoop.fs.FileSystem.get(fs_uri, hadoop_conf)
    return fs


def _find_most_recent_file(spark_client: SparkClient, base_path: str) -> str:
    """List parquet files in the S3 directory and return the one uploaded most recently (by S3 last-modified)."""
    fs = _get_hadoop_fs(spark_client, base_path)
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
    logger.info(
        f"m=_find_most_recent_file, msg=Found {len(candidates)} files, most recently uploaded: {most_recent_filename}"
    )
    return f"{base_path}/{most_recent_filename}"


def _find_most_recent_date_folder(spark_client: SparkClient, base_path: str) -> str:
    """List date-named subfolders (YYYY-MM-DD) and return the path of the most recent one."""
    fs = _get_hadoop_fs(spark_client, base_path)
    path = spark_client.conn._jvm.org.apache.hadoop.fs.Path(base_path)

    statuses = fs.listStatus(path)
    candidates = []
    for file_status in statuses:
        if not file_status.isDirectory():
            continue
        folder_name = file_status.getPath().getName()
        if DATE_FOLDER_PATTERN.match(folder_name):
            candidates.append(folder_name)

    if not candidates:
        raise FileNotFoundError(f"No YYYY-MM-DD folders found in {base_path}")

    candidates.sort(reverse=True)
    most_recent = candidates[0]
    logger.info(
        f"m=_find_most_recent_date_folder, msg=Found {len(candidates)} date folders, most recent: {most_recent}"
    )
    return f"{base_path}/{most_recent}"


def _load_categorisation(
    spark_client,
    s3_consumer,
    s3_loader,
    args,
    partition_cols,
    file_date,
):
    """Load categorisation parquet from session-metadata."""
    environment = args.environment
    source = args.source
    table_name = args.table_name
    datalake_bucket = args.bucket

    base_path = _get_source_base_path(environment)
    if file_date:
        source_path = f"{base_path}/{file_date}.parquet"
        logger.info(
            f"m=_load_categorisation, msg=Using explicit file_date: {source_path}"
        )
    else:
        source_path = _find_most_recent_file(spark_client, base_path)
        logger.info(
            f"m=_load_categorisation, msg=Most recent file found: {source_path}"
        )

    db_info = DatalakeMetastoreService.get_db_info(
        env=environment, source=source, bucket=datalake_bucket
    )
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(write_database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    df = s3_consumer.get_data_from_file(path=source_path, format="parquet")
    df = df.withColumn("first_queue", F.col("first_queue").cast("string"))
    df = df.withColumn("last_queue", F.col("last_queue").cast("string"))

    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column("session_date")
        .output()
    )

    logger.info(
        f"m=_load_categorisation, msg=Loaded {df.count()} rows, "
        f"writing to {write_database_name}.{write_table_name}"
    )

    _write_to_datalake(
        df,
        s3_loader,
        spark_metastore_loader,
        spark_metastore_service,
        write_database_name,
        write_location,
        write_table_name,
        partition_cols,
    )


def _load_annotations(
    spark_client, s3_consumer, s3_loader, args, partition_cols, file_date
):
    """Load annotations by reading the index folder, resolving annotation keys, and writing to raw."""
    environment = args.environment
    source = args.source
    table_name = args.table_name
    datalake_bucket = args.bucket

    if environment != "prod":
        raise ValueError(
            f"This job only runs in prod (source bucket is prod-only). Got environment='{environment}'"
        )

    if file_date:
        index_folder_path = f"{SOURCE_ANNOTATIONS_INDEX_PATH}/{file_date}"
        logger.info(
            f"m=_load_annotations, msg=Using explicit date folder: {index_folder_path}"
        )
    else:
        try:
            index_folder_path = _find_most_recent_date_folder(
                spark_client, SOURCE_ANNOTATIONS_INDEX_PATH
            )
        except FileNotFoundError:
            logger.info(
                "m=_load_annotations, msg=No date folders found in annotations-index. "
                "No annotations to backfill — skipping gracefully."
            )
            return
        logger.info(
            f"m=_load_annotations, msg=Most recent index folder: {index_folder_path}"
        )

    fs = _get_hadoop_fs(spark_client, index_folder_path)
    folder_path = spark_client.conn._jvm.org.apache.hadoop.fs.Path(index_folder_path)
    if not fs.exists(folder_path):
        logger.info(
            f"m=_load_annotations, msg=Index folder does not exist: {index_folder_path}. "
            "No annotations for this date — skipping gracefully."
        )
        return

    index_files = fs.listStatus(folder_path)
    json_count = sum(1 for f in index_files if f.getPath().getName().endswith(".json"))
    if json_count == 0:
        logger.info(
            f"m=_load_annotations, msg=Index folder exists but contains 0 JSON files: {index_folder_path}. "
            "No annotations to backfill — skipping gracefully."
        )
        return

    logger.info(
        f"m=_load_annotations, msg=Found {json_count} index JSON files in {index_folder_path}"
    )

    index_schema = StructType(
        [
            StructField("session_id", StringType(), True),
            StructField("annotation_key", StringType(), True),
        ]
    )
    index_df = (
        spark_client.conn.read.format("json")
        .schema(index_schema)
        .load(f"{index_folder_path}/*.json")
    )

    annotation_keys = [
        row.annotation_key for row in index_df.select("annotation_key").collect()
    ]

    if not annotation_keys:
        logger.info(
            "m=_load_annotations, msg=Index files parsed but yielded 0 annotation keys — skipping"
        )
        return

    annotation_paths = [f"{SOURCE_BUCKET}/{key}" for key in annotation_keys]

    annotation_schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("session_id", StringType(), True),
            StructField("text", StringType(), True),
            StructField("author", StringType(), True),
            StructField("created_at", StringType(), True),
        ]
    )
    annotations_df = (
        spark_client.conn.read.format("json")
        .schema(annotation_schema)
        .load(annotation_paths)
    )

    annotations_df = annotations_df.select(
        F.col("id").alias("annotation_id"),
        F.col("session_id").alias("id_langfuse_session"),
        F.col("text").alias("annotation_text"),
        F.col("author"),
        F.to_timestamp("created_at").alias("created_at"),
    )

    annotations_df = (
        SparkDataFrameService()
        .input(annotations_df)
        .create_year_month_day_columns_from_dataframe_column("created_at")
        .output()
    )

    row_count = annotations_df.count()
    distinct_sessions = annotations_df.select("id_langfuse_session").distinct().count()
    distinct_authors = annotations_df.select("author").distinct().count()

    db_info = DatalakeMetastoreService.get_db_info(
        env=environment, source=source, bucket=datalake_bucket
    )
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(write_database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    _write_to_datalake(
        annotations_df,
        s3_loader,
        spark_metastore_loader,
        spark_metastore_service,
        write_database_name,
        write_location,
        write_table_name,
        partition_cols,
    )

    logger.info(
        f"m=_load_annotations, status=SUCCESS, "
        f"index_folder={index_folder_path}, "
        f"index_entries_resolved={len(annotation_keys)}, "
        f"annotations_written={row_count}, "
        f"distinct_sessions={distinct_sessions}, "
        f"distinct_authors={distinct_authors}, "
        f"target_table={write_database_name}.{write_table_name}, "
        f"msg=Annotations backfill complete"
    )


def _write_to_datalake(
    df,
    s3_loader,
    spark_metastore_loader,
    spark_metastore_service,
    database_name,
    database_location,
    table_name,
    partition_cols,
):
    """Common write logic: S3 + metastore + partitions."""
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


TABLE_LOADERS = {
    "categorisation": _load_categorisation,
    "annotations": _load_annotations,
}


def main() -> None:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("bucket", help="datalake bucket")
    parser.add_argument("source", help="schema name used for metastore resolution")
    parser.add_argument("table_name", help="name of the output table")
    parser.add_argument("partitions", help="JSON list of partition columns")
    parser.add_argument(
        "date",
        nargs="?",
        default="",
        help="Optional YYYY-MM-DD to load a specific file/folder (for backfills)",
    )

    add_validation_target_args(parser)
    args = parser.parse_args()
    table_name = args.table_name
    partition_cols = json.loads(args.partitions.replace("'", '"'))
    file_date = args.date.strip() if args.date else ""

    logger.info(
        f"m=__main__, environment={args.environment}, source={args.source}, "
        f"table_name={table_name}, file_date={file_date or '(auto-detect most recent)'}, "
        f"msg=Starting spark job..."
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    s3_loader = S3Loader()

    loader_fn = TABLE_LOADERS.get(table_name)
    if not loader_fn:
        raise ValueError(
            f"Unknown table_name '{table_name}'. Supported: {list(TABLE_LOADERS.keys())}"
        )

    loader_fn(spark_client, s3_consumer, s3_loader, args, partition_cols, file_date)

    logger.info(f"m=__main__, msg=Job completed successfully for table={table_name}")


if __name__ == "__main__":
    main()
