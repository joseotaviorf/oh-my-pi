"""
Generic Spark job that lands objects from any S3 bucket/prefix into a raw table.

Source config comes from `s3_ingestion_sources.<source_key>` in
`spark_jobs/{environment}_conf.yml`, so adding a source needs no code change.

The payload is kept verbatim in `raw_content`: an external app can change its export
contract without breaking ingestion, and parsing belongs to the clean layer.

Partitions come from each object's S3 LastModified in UTC, so a run rewrites exactly
the day partitions its load window covers — reruns and backfills are idempotent under
dynamic partition overwrite.
"""

from __future__ import annotations

import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timezone
from typing import Dict, List, Optional

import boto3

# Not `pyspark.sql.window`: the shared people pytest process mocks `pyspark.sql` in
# sys.modules, which breaks submodule imports when this module is under test.
from pyspark.sql import DataFrame, Window
from pyspark.sql import functions as F
from pyspark.sql.types import (
    IntegerType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

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

JOB_NAME = "load_s3_ingestion_raw"
DAG_NAME = "s3_ingestion"
SOURCES_CONFIG_KEY = "s3_ingestion_sources"
DATE_FMT = "%Y-%m-%d"

READ_MODE_WHOLE_FILE = "whole_file"
READ_MODE_LINES = "lines"
READ_MODES = (READ_MODE_WHOLE_FILE, READ_MODE_LINES)

EXTRACTION_TYPE_FULL = "full"
EXTRACTION_TYPE_INCREMENTAL = "incremental"
EXTRACTION_TYPES = (EXTRACTION_TYPE_FULL, EXTRACTION_TYPE_INCREMENTAL)
PARTITION_OVERWRITE_MODE_KEY = "spark.sql.sources.partitionOverwriteMode"

# input_file_name() reports whatever scheme the reader used (s3://, s3a://, s3n://).
S3_URI_SCHEME_AND_BUCKET = r"^s3[a-z]*://[^/]+/"

FILE_INDEX_SCHEMA = StructType(
    [
        StructField("file_key", StringType(), False),
        StructField("ts_file_modified", TimestampType(), False),
        StructField("year", IntegerType(), False),
        StructField("month", IntegerType(), False),
        StructField("day", IntegerType(), False),
    ]
)

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = logging.getLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn
metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
    spark_client
)


def resolve_source_config(source_key: str, config_service=None) -> Dict:
    """Return the `s3_ingestion_sources.<source_key>` entry for the current env."""
    config_service = (
        ConfigurationService(DAG_NAME) if config_service is None else config_service
    )
    sources = config_service.get_config(SOURCES_CONFIG_KEY) or {}
    if source_key not in sources:
        raise KeyError(
            f"m={JOB_NAME}, msg=source_key '{source_key}' is not declared under "
            f"{SOURCES_CONFIG_KEY} in the environment conf, "
            f"available={sorted(sources)}"
        )

    source = dict(sources[source_key])
    for required in ("bucket", "prefix"):
        if not source.get(required):
            raise ValueError(
                f"m={JOB_NAME}, msg={SOURCES_CONFIG_KEY}.{source_key}.{required} "
                "is required and must not be empty"
            )

    read_mode = str(source.get("read_mode", READ_MODE_WHOLE_FILE)).lower()
    if read_mode not in READ_MODES:
        raise ValueError(
            f"m={JOB_NAME}, msg=Unsupported read_mode '{read_mode}' for "
            f"source_key={source_key}. Supported: {', '.join(READ_MODES)}"
        )

    return {
        "bucket": source["bucket"],
        "prefix": source["prefix"].strip("/"),
        "file_suffix": source.get("file_suffix") or "",
        "read_mode": read_mode,
        "ingest_all_files": bool(source.get("ingest_all_files", False)),
    }


def list_source_objects(
    s3_client, bucket: str, prefix: str, file_suffix: str = ""
) -> List[Dict]:
    """
    Return `{key, last_modified}` for every readable object under `prefix`.

    Skips prefix placeholders and zero-byte objects: never part of an export.
    """
    paginator = s3_client.get_paginator("list_objects_v2")
    suffix = file_suffix.lower()
    objects: List[Dict] = []
    for page in paginator.paginate(Bucket=bucket, Prefix=f"{prefix}/"):
        for obj in page.get("Contents") or []:
            key = obj["Key"]
            if key.endswith("/") or obj.get("Size", 0) == 0:
                continue
            if suffix and not key.lower().endswith(suffix):
                continue
            objects.append({"key": key, "last_modified": obj["LastModified"]})
    return objects


def filter_objects_by_window(
    objects: List[Dict],
    load_start_date: str,
    load_end_date: str,
    ingest_all_files: bool = False,
) -> List[Dict]:
    """
    Keep the objects whose UTC LastModified date falls in the inclusive load window.

    `ingest_all_files` bypasses it, for sources that keep rewriting the same keys.
    """
    if ingest_all_files:
        return list(objects)

    dt_start = datetime.strptime(load_start_date, DATE_FMT).date()
    dt_end = datetime.strptime(load_end_date, DATE_FMT).date()
    if dt_start > dt_end:
        raise ValueError(
            f"m={JOB_NAME}, msg=load_start_date ({load_start_date}) must be "
            f"<= load_end_date ({load_end_date})"
        )

    return [
        obj
        for obj in objects
        if dt_start <= obj["last_modified"].astimezone(timezone.utc).date() <= dt_end
    ]


def build_file_index_df(objects: List[Dict], spark_session=None) -> DataFrame:
    """Build the object-metadata side of the join: key, modified time, partitions."""
    spark_session = spark if spark_session is None else spark_session
    rows = []
    for obj in objects:
        # Kept timezone-aware: a naive datetime would be read back in the session
        # timezone and shift the recorded instant.
        modified_utc = obj["last_modified"].astimezone(timezone.utc)
        rows.append(
            (
                obj["key"],
                modified_utc,
                modified_utc.year,
                modified_utc.month,
                modified_utc.day,
            )
        )
    return spark_session.createDataFrame(rows, schema=FILE_INDEX_SCHEMA)


def read_source_files(
    bucket: str, objects: List[Dict], read_mode: str, spark_session=None
) -> DataFrame:
    """
    Read the listed objects and return `file_key`, `line_number`, `raw_content`.

    Reads the explicit key list rather than a glob, so the load window stays
    authoritative and objects outside it are never re-read.
    """
    spark_session = spark if spark_session is None else spark_session
    paths = [f"s3://{bucket}/{obj['key']}" for obj in objects]

    reader = spark_session.read
    if read_mode == READ_MODE_WHOLE_FILE:
        reader = reader.option("wholetext", "true")
    raw = reader.text(paths)

    with_key = raw.select(
        F.regexp_replace(F.input_file_name(), S3_URI_SCHEME_AND_BUCKET, "").alias(
            "file_key"
        ),
        F.col("value").alias("raw_content"),
    ).where(F.length(F.col("raw_content")) > 0)

    if read_mode == READ_MODE_WHOLE_FILE:
        return with_key.withColumn("line_number", F.lit(1)).select(
            "file_key", "line_number", "raw_content"
        )

    # Tie-break on id() so duplicate lines number deterministically, keeping
    # [file_name, line_number] a stable merge key across reruns.
    window = Window.partitionBy("file_key").orderBy(
        F.col("raw_content"), F.monotonically_increasing_id()
    )
    return with_key.withColumn("line_number", F.row_number().over(window)).select(
        "file_key", "line_number", "raw_content"
    )


def build_raw_dataframe(
    bucket: str, objects: List[Dict], read_mode: str, spark_session=None
) -> DataFrame:
    """Join file contents with object metadata into the final raw-layer schema."""
    content_df = read_source_files(bucket, objects, read_mode, spark_session)
    index_df = build_file_index_df(objects, spark_session)

    return (
        content_df.join(F.broadcast(index_df), on="file_key", how="inner")
        .withColumn("file_name", F.concat(F.lit(f"s3://{bucket}/"), F.col("file_key")))
        .withColumn("ts_load", F.current_timestamp())
        .select(
            "file_name",
            "line_number",
            "raw_content",
            "ts_file_modified",
            "ts_load",
            "year",
            "month",
            "day",
        )
    )


def resolve_write_mode(
    extraction_type: str, partition_cols: List[str], spark_session=None
) -> str:
    """
    Return the S3 write mode for `extraction_type`, refusing an unsafe session.

    An incremental run replaces only the day partitions present in the DataFrame,
    which requires dynamic partition overwrite. Under the static default the very
    same write would drop every other partition in the table, and S3Loader only logs
    that mismatch instead of failing — so it is enforced here.
    """
    extraction_type = extraction_type.lower()
    if extraction_type not in EXTRACTION_TYPES:
        raise ValueError(
            f"m={JOB_NAME}, msg=Unsupported extraction_type '{extraction_type}'. "
            f"Supported: {', '.join(EXTRACTION_TYPES)}"
        )

    if extraction_type == EXTRACTION_TYPE_FULL:
        return "overwrite"

    if not partition_cols:
        raise ValueError(
            f"m={JOB_NAME}, msg=extraction_type '{EXTRACTION_TYPE_INCREMENTAL}' "
            "requires partitions; declare them in tables_customization"
        )

    spark_session = spark if spark_session is None else spark_session
    overwrite_mode = str(
        spark_session.conf.get(PARTITION_OVERWRITE_MODE_KEY, "static")
    ).lower()
    if overwrite_mode != "dynamic":
        raise RuntimeError(
            f"m={JOB_NAME}, msg={PARTITION_OVERWRITE_MODE_KEY} is "
            f"'{overwrite_mode}', but an incremental load needs 'dynamic' to avoid "
            "replacing partitions outside the load window"
        )
    return "overwrite"


def parse_arguments() -> Dict[str, Optional[str]]:
    """Parse the positional Spark-job arguments plus cluster-validation flags."""
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod")
    parser.add_argument("bucket", help="Datalake destination bucket")
    parser.add_argument("schema", help="Raw schema receiving the table")
    parser.add_argument("table_name", help="Destination raw table name")
    parser.add_argument("partitions", help="JSON list of partition columns")
    parser.add_argument("extraction_type", help="full or incremental")
    parser.add_argument("load_start_date", help="First UTC day inclusive (YYYY-MM-DD)")
    parser.add_argument("load_end_date", help="Last UTC day inclusive (YYYY-MM-DD)")
    parser.add_argument(
        "source_key",
        nargs="?",
        default=None,
        help=(
            f"Key under {SOURCES_CONFIG_KEY} in the environment conf. "
            "Defaults to table_name."
        ),
    )

    add_validation_target_args(parser)
    args = parser.parse_args()

    return {
        "environment": args.environment,
        "bucket": args.bucket,
        "schema": args.schema,
        "table_name": args.table_name,
        "partitions": args.partitions,
        "extraction_type": args.extraction_type,
        "load_start_date": args.load_start_date,
        "load_end_date": args.load_end_date,
        "source_key": args.source_key or args.table_name,
        "target_database_name": args.target_database_name,
        "target_table_name": args.target_table_name,
    }


def run(job_args: Optional[Dict[str, Optional[str]]] = None, s3_client=None) -> None:
    """Entry point used by `__main__` and unit tests."""
    job_args = parse_arguments() if job_args is None else job_args

    environment = job_args["environment"]
    bucket = job_args["bucket"]
    schema = job_args["schema"]
    table_name = job_args["table_name"]
    source_key = job_args["source_key"]
    partition_cols = json.loads(job_args["partitions"].replace("'", '"'))
    write_mode = resolve_write_mode(job_args["extraction_type"], partition_cols)

    source = resolve_source_config(source_key)
    s3_client = boto3.client("s3") if s3_client is None else s3_client

    objects = list_source_objects(
        s3_client, source["bucket"], source["prefix"], source["file_suffix"]
    )
    selected = filter_objects_by_window(
        objects,
        job_args["load_start_date"],
        job_args["load_end_date"],
        source["ingest_all_files"],
    )

    logger.info(
        f"m=run, source_key={source_key}, source_bucket={source['bucket']}, "
        f"source_prefix={source['prefix']}, read_mode={source['read_mode']}, "
        f"load_start_date={job_args['load_start_date']}, "
        f"load_end_date={job_args['load_end_date']}, listed_objects={len(objects)}, "
        f"selected_objects={len(selected)}, "
        f"extraction_type={job_args['extraction_type']}, write_mode={write_mode}, "
        f"destination={schema}.{table_name}"
    )

    if not selected:
        logger.warning(
            f"m=run, source_key={source_key}, msg=No object matched the load window; "
            "skipping write and metastore update"
        )
        return

    df_out = build_raw_dataframe(source["bucket"], selected, source["read_mode"])

    db_info = DatalakeMetastoreService.get_db_info(environment, schema, bucket)
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=db_info["db_raw_databricks"],
            prod_table=table_name,
            prod_location=db_info["db_raw_path"],
            bucket=bucket,
            target_database=job_args["target_database_name"],
            target_table=job_args["target_table_name"],
        )
    )
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    metastore_service.create_database(write_database_name)
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    S3Loader().load_df(
        df=df_out,
        s3_path=f"{write_location}{write_table_name}",
        format_options=format_options,
        partitions=partition_cols,
        write_mode=write_mode,
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
        f"m=run, msg=Successfully ingested {len(selected)} object(s) from "
        f"s3://{source['bucket']}/{source['prefix']} into "
        f"{write_database_name}.{write_table_name}"
    )


if __name__ == "__main__":
    run()
