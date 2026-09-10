"""
Generic Spark job that exports a reverse-layer lake table to an S3 object.

Reads `{schema}.{table_name}` and writes a single object to
`s3://{bucket}/{key}` in the requested `file_format`. Destination bucket, key,
format, and optional object ACL are declaration-driven
(`extra_spark_job_arguments`), so the same job can publish to an internal
bucket or to an external partner bucket.

Supported file_format values: csv, json, parquet.

Two write modes:

1. **Single-object** (default) — Spark's DataFrameWriter always treats its
   target path as a directory of part files, even with `coalesce(1)`. Consumers
   read one object (e.g. `orghealth/base_app_org_health.csv`), so the job writes
   to a throwaway staging prefix under the destination key's parent directory,
   copies the single part file onto the exact destination key via boto3, and
   deletes the staging prefix. `coalesce(1)` is required for that promote step.

2. **Partitioned Parquet** — when the fifth argument lists partition columns
   (comma-separated, e.g. `year,month,day`), the job writes a Hadoop-style
   partitioned dataset directly under `s3a://{bucket}/{key_prefix}/` with ZSTD
   compression and no staging promote.

   `s3a://` is deliberate: `s3://` resolves to EMRFS on EMR, and the partner
   integration (access point alias, `fs.s3a.bucket.probe=0`, no magic committer)
   was specified against Hadoop 3.4.1 S3A. The scheme also decides whether the
   cluster-wide `fs.s3a.*` settings apply at all.

   Partition overwrite is forced to `dynamic` so a daily run replaces only its
   own `year=/month=/day=` partition. Under Spark's default `static` mode,
   `mode("overwrite")` + `partitionBy` deletes the whole destination prefix and
   would leave the consumer with a single day instead of the agreed daily
   snapshot history.

   No canned ACL is set on this path, but note that EMR spark-submit injects
   `spark.hadoop.fs.s3a.canned.acl=BucketOwnerFullControl` for every job in this
   repo (`job_cluster_engine._build_emr_extra_spark_submit_args`), so S3A PUTs
   still carry `x-amz-acl: bucket-owner-full-control`. Buckets with ACLs
   disabled (`ObjectOwnership=BucketOwnerEnforced`) accept that specific value;
   a bucket policy that denies `s3:x-amz-acl` outright would not, and the fix
   belongs at submit time, not here.

CSV options match the Daily Pipeline notebook Spark writer (`header=true`
plus Spark CSV defaults: comma separator, UTF-8, backslash escape). Do not
switch to pandas quote-doubling; partner apps already consume the Spark file.

Outside prod, the declared bucket/key are ignored and the export is redirected
to `people_bucket` under `reverse_s3_test/`. ENVIRONMENT must be set
explicitly; a missing value fails the job instead of defaulting to prod.
Object ACL is applied only on the prod path (partner buckets); Forno writes to
an internal bucket that typically rejects canned ACLs.
"""

import os
import uuid
from argparse import ArgumentParser
from typing import Any, Dict, Iterable, List, Optional, Tuple

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.validation.spark_args import (
    CLI_NONE,
    add_validation_target_args,
    decode_cli_arg,
    is_validation_run,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_to_s3"
CROSS_ACCOUNT_OBJECT_ACL = "bucket-owner-full-control"
S3_DELETE_BATCH_SIZE = 1000
NON_PROD_KEY_PREFIX = "reverse_s3_test"

spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn
logger = QuintoAndarLogger(JOB_NAME)

_CONTENT_TYPES = {
    "csv": "text/csv",
    "json": "application/json",
    "parquet": "application/vnd.apache.parquet",
}


def _write_csv(df, s3_uri: str) -> None:
    """
    Write `df` as a single-partition CSV directory at `s3_uri`.

    Matches the Org Health notebook: `header=true` and Spark CSV defaults
    (comma, UTF-8, empty nulls, backslash escape). Spark's escape is not
    pandas `to_csv` quote-doubling.
    """
    (
        df.coalesce(1)
        .write.mode("overwrite")
        .option("header", "true")
        .option("nullValue", "")
        .option("emptyValue", "")
        .option("encoding", "UTF-8")
        .csv(s3_uri)
    )


def _write_json(df, s3_uri: str) -> None:
    """Write `df` as a single-partition JSON directory at `s3_uri`."""
    df.coalesce(1).write.mode("overwrite").json(s3_uri)


def _write_parquet(df, s3_uri: str) -> None:
    """Write `df` as a single-partition Parquet directory at `s3_uri`."""
    df.coalesce(1).write.mode("overwrite").parquet(s3_uri)


def _write_partitioned_parquet(df, s3_uri: str, partition_columns: List[str]) -> None:
    """
    Write `df` as ZSTD-compressed Parquet partitioned by `partition_columns`.

    Forces `partitionOverwriteMode=dynamic` so `mode("overwrite")` replaces only
    the partitions present in `df`. Spark's default (`static`) deletes the entire
    destination path first, which would drop every previously exported day.
    """
    df.sparkSession.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")
    (
        df.write.mode("overwrite")
        .option("compression", "zstd")
        .partitionBy(*partition_columns)
        .parquet(s3_uri)
    )


_WRITERS = {
    "csv": _write_csv,
    "json": _write_json,
    "parquet": _write_parquet,
}


def _parse_partition_columns(raw_value: Optional[str]) -> Optional[List[str]]:
    """Return trimmed partition column names from a comma-separated CLI value."""
    if raw_value is None or not raw_value.strip():
        return None
    columns = [column.strip() for column in raw_value.split(",") if column.strip()]
    return columns or None


def _as_prefix(prefix: str) -> str:
    """Return `prefix` with a trailing slash so S3 listing cannot collide."""
    return prefix.rstrip("/") + "/"


def _staging_prefix_for_destination(destination_key: str, table_name: str) -> str:
    """
    Return a throwaway staging prefix scoped under the destination directory.

    For `orghealth/base_app_org_health.csv` the staging path is
    `orghealth/_staging/load_to_s3/{table_name}-{uuid}` so prefix-scoped IAM on
    `orghealth/*` covers Spark Put/Get/List/Delete during promote. Keys without
    a `/` fall back to `_staging/` at the bucket root.
    """
    key = destination_key.strip("/")
    if "/" in key:
        parent_dir = key.rsplit("/", 1)[0]
        return f"{parent_dir}/_staging/{JOB_NAME}/{table_name}-{uuid.uuid4().hex}"
    return f"_staging/{JOB_NAME}/{table_name}-{uuid.uuid4().hex}"


def _is_spark_part_file(key: str) -> bool:
    """
    Return True when `key` is a Spark data part file, not `_SUCCESS` or CRC.

    Spark 3 usually writes `part-00000-…-c000.csv`; Hadoop may omit the
    extension. Hidden files and checksums must not be promoted.
    """
    name = key.rsplit("/", 1)[-1]
    if not name.startswith("part-"):
        return False
    if name.endswith(".crc") or name.startswith("."):
        return False
    return True


def _list_object_keys(s3_client, bucket: str, prefix: str) -> List[str]:
    """Return every object key under `prefix` in `bucket`."""
    paginator = s3_client.get_paginator("list_objects_v2")
    keys = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents") or []:
            keys.append(obj["Key"])
    return keys


def _delete_keys(s3_client, bucket: str, keys: Iterable[str]) -> None:
    """
    Delete `keys` from `bucket` in batches of `S3_DELETE_BATCH_SIZE`.

    boto3 `delete_objects` accepts at most 1000 keys per call.
    """
    pending = []
    for key in keys:
        pending.append({"Key": key})
        if len(pending) == S3_DELETE_BATCH_SIZE:
            s3_client.delete_objects(Bucket=bucket, Delete={"Objects": pending})
            pending = []
    if pending:
        s3_client.delete_objects(Bucket=bucket, Delete={"Objects": pending})


def _delete_prefix(s3_client, bucket: str, prefix: str) -> None:
    """
    Best-effort delete of every object under `prefix`.

    Staging leftover and a prior Spark directory at the destination key must
    not fail the job after `copy_object` already wrote the consumer object.
    Missing `s3:DeleteObject` is logged and ignored.
    """
    try:
        keys = _list_object_keys(s3_client, bucket, _as_prefix(prefix))
        if keys:
            _delete_keys(s3_client, bucket, keys)
    except Exception as exc:
        logger.warning(
            f"m={JOB_NAME}, msg=failed to delete prefix, bucket={bucket}, "
            f"prefix={prefix}, error={exc}"
        )


def _promote_single_part_file_to_key(
    bucket: str,
    staging_prefix: str,
    destination_key: str,
    file_format: str,
    s3_client,
    object_acl: Optional[str] = None,
) -> None:
    """
    Copy the single Spark part file under `staging_prefix` onto `destination_key`.

    Removes leftover objects under `destination_key/` (a prior Spark directory
    write at the same path) before copying so consumers always GET one object.
    Staging cleanup is the caller's responsibility (`try`/`finally`).
    """
    staging_list_prefix = _as_prefix(staging_prefix)
    part_keys = [
        key
        for key in _list_object_keys(s3_client, bucket, staging_list_prefix)
        if _is_spark_part_file(key)
    ]
    if len(part_keys) != 1:
        raise RuntimeError(
            f"m={JOB_NAME}, msg=Expected exactly one part file under staging prefix, "
            f"bucket={bucket}, staging_prefix={staging_prefix}, found={len(part_keys)}"
        )

    _delete_prefix(s3_client, bucket, destination_key)

    copy_kwargs = {
        "Bucket": bucket,
        "CopySource": {"Bucket": bucket, "Key": part_keys[0]},
        "Key": destination_key,
        "ContentType": _CONTENT_TYPES[file_format],
        "MetadataDirective": "REPLACE",
    }
    if object_acl:
        copy_kwargs["ACL"] = object_acl

    s3_client.copy_object(**copy_kwargs)


def _resolve_destination(bucket: str, key_prefix: str) -> Tuple[str, str, bool]:
    """
    Resolve the write destination from ENVIRONMENT.

    Returns `(bucket, key_prefix, apply_object_acl)`. Prod uses the declared
    destination and applies a canned ACL when the caller provided one. Any
    other environment redirects to `people_bucket` under `reverse_s3_test/`
    and never applies ACL (internal buckets typically reject it).

    Raises:
        RuntimeError: ENVIRONMENT is missing or blank.
    """
    environment = os.environ.get("ENVIRONMENT")
    if environment is None or not environment.strip():
        raise RuntimeError(
            f"m={JOB_NAME}, msg=ENVIRONMENT is required and must not be empty"
        )

    environment = environment.strip().lower()
    if environment == "prod":
        return bucket, key_prefix, True

    test_bucket = ConfigurationService().get_config("people_bucket")
    test_key_prefix = f"{NON_PROD_KEY_PREFIX}/{key_prefix.strip('/')}"
    logger.info(
        f"m={JOB_NAME}, msg=non-prod environment, redirecting export, "
        f"environment={environment}, declared_bucket={bucket}, "
        f"declared_key_prefix={key_prefix}, test_bucket={test_bucket}, "
        f"test_key_prefix={test_key_prefix}"
    )
    return test_bucket, test_key_prefix, False


def parse_arguments() -> Dict[str, Any]:
    """Parse positional Spark-job arguments plus cluster-validation flags."""
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("schema", help="Reverse schema where the table lives")
    parser.add_argument("table_name", help="Name of the table to export")
    parser.add_argument("bucket", help="Destination S3 bucket (no s3:// prefix)")
    parser.add_argument("key_prefix", help="Destination object key inside the bucket")
    parser.add_argument(
        "file_format",
        type=str.lower,
        choices=sorted(_WRITERS),
        help=f"Output file format. One of: {', '.join(sorted(_WRITERS))}",
    )
    parser.add_argument(
        "object_acl",
        nargs="?",
        type=decode_cli_arg,
        default=None,
        help=(
            "Optional canned ACL for single-object exports "
            f"(e.g. {CROSS_ACCOUNT_OBJECT_ACL}). Applied in prod only. "
            f"Pass '{CLI_NONE}' to skip it when partition columns follow."
        ),
    )
    parser.add_argument(
        "partition_columns",
        nargs="?",
        type=decode_cli_arg,
        default=None,
        help=(
            "Optional comma-separated partition columns for Parquet exports "
            "(e.g. year,month,day). Writes a Hadoop-style dataset."
        ),
    )

    add_validation_target_args(parser)
    args = parser.parse_args()

    return {
        "schema": args.schema,
        "table_name": args.table_name,
        "bucket": args.bucket,
        "key_prefix": args.key_prefix,
        "file_format": args.file_format,
        "object_acl": args.object_acl,
        "partition_columns": _parse_partition_columns(args.partition_columns),
        "target_database_name": args.target_database_name,
        "target_table_name": args.target_table_name,
    }


def load_table_into_s3(
    schema: str,
    table_name: str,
    bucket: str,
    key_prefix: str,
    file_format: str,
    object_acl: Optional[str] = None,
    partition_columns: Optional[List[str]] = None,
    spark_session=None,
    s3_client=None,
) -> None:
    """
    Export `{schema}.{table_name}` to S3.

    Single-object mode promotes one Spark part file onto `key_prefix`. Partitioned
    Parquet mode writes directly under `key_prefix/` with `partitionBy`.

    `spark_session` and `s3_client` default to the module Spark session and a
    new boto3 client so production stays dual-runtime; tests inject mocks.
    """
    file_format = file_format.lower()
    if file_format not in _WRITERS:
        raise ValueError(
            f"m={JOB_NAME}, msg=Unsupported file_format '{file_format}'. "
            f"Supported: {', '.join(sorted(_WRITERS))}"
        )
    if partition_columns and file_format != "parquet":
        raise ValueError(
            f"m={JOB_NAME}, msg=partition_columns requires file_format parquet, "
            f"got={file_format}"
        )

    spark_session = spark if spark_session is None else spark_session

    bucket, key_prefix, apply_object_acl = _resolve_destination(bucket, key_prefix)
    destination_key = key_prefix.strip("/")
    df = spark_session.table(f"{schema}.{table_name}")

    if partition_columns:
        destination_uri = f"s3a://{bucket}/{destination_key}/"
        logger.info(
            f"m={JOB_NAME}, msg=exporting partitioned table, "
            f"table={schema}.{table_name}, destination={destination_uri}, "
            f"partition_columns={partition_columns}"
        )
        _write_partitioned_parquet(df, destination_uri, partition_columns)
        logger.info(
            f"m={JOB_NAME}, msg=partitioned export finished, "
            f"destination={destination_uri}"
        )
        return

    s3_client = boto3.client("s3") if s3_client is None else s3_client
    writer = _WRITERS[file_format]
    effective_acl = object_acl if apply_object_acl else None
    staging_prefix = _staging_prefix_for_destination(destination_key, table_name)
    staging_uri = f"s3://{bucket}/{staging_prefix}"

    logger.info(
        f"m={JOB_NAME}, msg=exporting table, table={schema}.{table_name}, "
        f"destination=s3://{bucket}/{destination_key}, file_format={file_format}"
    )

    try:
        writer(df, staging_uri)
        _promote_single_part_file_to_key(
            bucket=bucket,
            staging_prefix=staging_prefix,
            destination_key=destination_key,
            file_format=file_format,
            s3_client=s3_client,
            object_acl=effective_acl,
        )
    finally:
        _delete_prefix(s3_client, bucket, staging_prefix)

    logger.info(
        f"m={JOB_NAME}, msg=export finished, destination=s3://{bucket}/{destination_key}"
    )


def run(job_args: Optional[Dict[str, Any]] = None) -> None:
    """
    Entry point used by `__main__` and unit tests.

    Skips the export when cluster-validation flags are present.
    """
    job_args = parse_arguments() if job_args is None else job_args

    if is_validation_run(
        job_args["target_database_name"],
        job_args["target_table_name"],
    ):
        logger.info(
            f"m={JOB_NAME}, msg=Skipping reverse S3 export in cluster validation mode"
        )
        return

    load_table_into_s3(
        schema=job_args["schema"],
        table_name=job_args["table_name"],
        bucket=job_args["bucket"],
        key_prefix=job_args["key_prefix"],
        file_format=job_args["file_format"],
        object_acl=job_args.get("object_acl"),
        partition_columns=job_args.get("partition_columns"),
    )


if __name__ == "__main__":
    run()
