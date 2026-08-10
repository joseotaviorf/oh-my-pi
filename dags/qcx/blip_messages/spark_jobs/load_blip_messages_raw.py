#!/usr/bin/env python3
"""Load Consórcio Blip chat JSONL (backfill + incremental) into raw Delta.

Incoming layout (prod data-science bucket):
  {incoming_base_path}/backfill/{from_unix}_{to_unix}/batch_*.jsonl
  {incoming_base_path}/incremental/{job_start_unix}.jsonl

Ignored ops artifacts: done.jsonl, errors.jsonl, _SUCCESS (backfill);
watermark.json, *.errors.jsonl (incremental).

Discovery:
  Backfill and incremental both listed via boto3 (reliable ETags).
  Incremental: watermark = max job_start_unix already success in the ledger;
  S3 LIST uses StartAfter that key so only newer objects are returned.
  Per file: skip when ledger has status=success and the same etag. Failed keys
  and etag changes are reprocessed.

Dedupe guarantee (row level):
  Insert-only MERGE on id_message — first ingested row wins; later files with
  the same id_message are ignored. s3_key reflects the winning file.
  Producer tunnel_id is landed as id_tunnel (lake id_* convention).

File ledger (best-effort skip + audit):
  blip_messages_ingest_files tracks each processed object. The CLI owns when
  files appear; this job only records whether each file was ingested. Ledger
  rows are committed only after the message MERGE for that file succeeds.
  If the ledger is lost, a full re-scan is still safe (no duplicate messages).

source column:
  Preserved from producer JSONL (blip_cli_backfill / blip_cli_incremental).
  When missing, derived from the S3 prefix family. Rows whose source disagrees
  with the prefix family are rejected.
"""

from __future__ import annotations

import argparse
import ast
import re
from dataclasses import dataclass
from typing import Dict, List, Optional, Set, Tuple

import boto3
from botocore.exceptions import ClientError
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (
    IntegerType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_blip_messages_raw"
DAG_NAME = "blip_messages"
INGEST_FILES_TABLE = "blip_messages_ingest_files"
BACKFILL_RUN_ID_RE = re.compile(r"/backfill/(\d+_\d+)/")
INCREMENTAL_UNIX_RE = re.compile(r"/incremental/(\d+)\.jsonl$")
BACKFILL_SOURCE = "blip_cli_backfill"
INCREMENTAL_SOURCE = "blip_cli_incremental"
MERGE_ON = ["id_message"]
LEDGER_MERGE_ON = ["s3_key"]
MESSAGE_COLUMNS = [
    "id_lead",
    "whatsapp_identity",
    "tunnel_id",
    "id_crm",
    "id_message",
    "host_name",
    "role",
    "content",
    "ts_created",
    "year",
    "month",
    "day",
    "source",
]

logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn
metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
    spark_client
)


@dataclass(frozen=True)
class S3ObjectRef:
    uri: str
    bucket: str
    key: str
    etag: str
    size_bytes: int


@dataclass
class LedgerState:
    success_etag_by_key: Dict[str, str]
    failed_keys: Set[str]
    incremental_watermark_unix: Optional[int]


def parse_args() -> argparse.Namespace:
    arg_parser = argparse.ArgumentParser(description=JOB_NAME)
    arg_parser.add_argument("environment", help="forno or prod")
    arg_parser.add_argument(
        "bucket", help="5a-datalake-<env> bucket name or full s3:// path"
    )
    arg_parser.add_argument(
        "schema", help="Schema name without datalake_ prefix or _raw suffix"
    )
    arg_parser.add_argument("table_name", help="Raw table name")
    arg_parser.add_argument("partitions", help="e.g. ['year','month','day']")
    arg_parser.add_argument(
        "dag_run_id",
        help="Airflow dag_run.run_id for ingest-file ledger provenance",
    )
    add_validation_target_args(arg_parser)
    args = arg_parser.parse_args()
    args.partition_cols = ast.literal_eval(args.partitions)
    return args


def main() -> None:
    args = parse_args()
    conf = ConfigurationService(DAG_NAME)
    incoming_base = conf.get_config("incoming_base_path").rstrip("/")

    datalake_bucket = args.bucket.replace("s3://", "").replace("s3a://", "")
    db_info = DatalakeMetastoreService.get_db_info(
        args.environment, args.schema, datalake_bucket
    )
    messages_database, messages_table, messages_location = (
        resolve_datalake_write_target(
            prod_database=db_info["db_raw_databricks"],
            prod_table=args.table_name,
            prod_location=db_info["db_raw_path"],
            bucket=datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )
    full_messages_table = f"{messages_database}.{messages_table}"
    messages_path = f"{messages_location.rstrip('/')}/{messages_table}"

    ledger_database, ledger_table, ledger_location = resolve_datalake_write_target(
        prod_database=db_info["db_raw_databricks"],
        prod_table=INGEST_FILES_TABLE,
        prod_location=db_info["db_raw_path"],
        bucket=datalake_bucket,
        target_database=args.target_database_name,
        target_table=INGEST_FILES_TABLE,
    )
    full_ledger_table = f"{ledger_database}.{ledger_table}"
    ledger_path = f"{ledger_location.rstrip('/')}/{ledger_table}"

    ledger = _load_ledger_state(spark, full_ledger_table)
    candidates = _discover_candidates(incoming_base, ledger)
    to_process = [obj for obj in candidates if _needs_processing(obj, ledger)]

    logger.info(
        f"m=main, env={args.environment}, incoming_base={incoming_base}, "
        f"incremental_watermark={ledger.incremental_watermark_unix}, "
        f"n_candidates={len(candidates)}, n_process={len(to_process)}, "
        f"dag_run_id={args.dag_run_id}"
    )

    metastore_service.create_database(messages_database)
    if not to_process:
        _bootstrap_empty_tables(
            spark,
            full_messages_table,
            messages_path,
            full_ledger_table,
            ledger_path,
            args.partition_cols,
        )
        logger.info("m=main, msg=No new Blip message files to ingest. Exiting.")
        return

    loader = DeltaLoader()
    ok_files = 0
    failed_files = 0

    for obj in to_process:
        try:
            row_count = _ingest_file(
                obj=obj,
                loader=loader,
                full_messages_table=full_messages_table,
                messages_path=messages_path,
                partition_cols=args.partition_cols,
            )
            _upsert_ledger_row(
                loader=loader,
                full_ledger_table=full_ledger_table,
                ledger_path=ledger_path,
                obj=obj,
                dag_run_id=args.dag_run_id,
                status="success",
                row_count=row_count,
            )
            ledger.success_etag_by_key[obj.key] = obj.etag
            ledger.failed_keys.discard(obj.key)
            ok_files += 1
        except Exception as exc:
            failed_files += 1
            logger.error(
                f"m=main, s3_key={obj.key}, etag={obj.etag}, error={exc}, "
                "msg=File ingest failed; recording ledger status=failed"
            )
            _upsert_ledger_row(
                loader=loader,
                full_ledger_table=full_ledger_table,
                ledger_path=ledger_path,
                obj=obj,
                dag_run_id=args.dag_run_id,
                status="failed",
                row_count=0,
            )
            ledger.failed_keys.add(obj.key)

    logger.info(
        f"m=main, msg=Blip ingest finished, ok_files={ok_files}, "
        f"failed_files={failed_files}"
    )
    if failed_files:
        raise RuntimeError(
            f"Blip ingest finished with {failed_files} failed file(s) "
            f"({ok_files} succeeded)"
        )


def _discover_candidates(incoming_base: str, ledger: LedgerState) -> List[S3ObjectRef]:
    refs: List[S3ObjectRef] = []
    refs.extend(_discover_backfill(incoming_base))
    refs.extend(_discover_incremental(incoming_base, ledger))
    return sorted(refs, key=lambda ref: ref.key)


def _discover_backfill(incoming_base: str) -> List[S3ObjectRef]:
    """List backfill batch_*.jsonl via boto3 (reliable ETags, same as incremental)."""
    bucket, base_key = _parse_s3_uri(incoming_base)
    prefix = f"{base_key}/backfill/".lstrip("/")
    refs = [
        ref
        for ref in _list_s3_objects(
            bucket=bucket, prefix=prefix, start_after=None, suffix=".jsonl"
        )
        if _is_message_object(ref.key)
    ]
    logger.info(f"m=_discover_backfill, n_batch_candidates={len(refs)}")
    return refs


def _discover_incremental(incoming_base: str, ledger: LedgerState) -> List[S3ObjectRef]:
    """List incremental JSONL with StartAfter the watermark key when possible."""
    bucket, base_key = _parse_s3_uri(incoming_base)
    prefix = f"{base_key}/incremental/".lstrip("/")
    start_after = None
    if ledger.incremental_watermark_unix is not None:
        start_after = f"{prefix}{ledger.incremental_watermark_unix}.jsonl"

    refs = _list_s3_objects(
        bucket=bucket,
        prefix=prefix,
        start_after=start_after,
        suffix=".jsonl",
    )
    # StartAfter skips the watermark key itself — re-head it for etag changes.
    if ledger.incremental_watermark_unix is not None:
        watermark_key = f"{prefix}{ledger.incremental_watermark_unix}.jsonl"
        try:
            refs.append(_head_object(bucket, watermark_key))
        except ClientError:
            logger.warning(
                f"m=_discover_incremental, key={watermark_key}, "
                "msg=Watermark object missing; continuing with newer keys only"
            )
    # Always re-include failed incremental keys (may be older than watermark).
    for failed_key in ledger.failed_keys:
        if "/incremental/" not in failed_key:
            continue
        if any(ref.key == failed_key for ref in refs):
            continue
        try:
            refs.append(_head_object(bucket, failed_key))
        except ClientError:
            logger.warning(
                f"m=_discover_incremental, key={failed_key}, "
                "msg=Failed ledger key no longer in S3; skipping"
            )

    filtered = []
    seen: Set[str] = set()
    for ref in refs:
        if ref.key in seen or not _is_message_object(ref.key):
            continue
        unix = _incremental_unix(ref.key)
        if unix is None:
            continue
        if (
            ledger.incremental_watermark_unix is not None
            and unix < ledger.incremental_watermark_unix
            and ref.key not in ledger.failed_keys
        ):
            continue
        seen.add(ref.key)
        filtered.append(ref)

    logger.info(
        f"m=_discover_incremental, watermark={ledger.incremental_watermark_unix}, "
        f"start_after={start_after}, n_candidates={len(filtered)}"
    )
    return filtered


def _needs_processing(obj: S3ObjectRef, ledger: LedgerState) -> bool:
    if obj.key in ledger.failed_keys:
        return True
    success_etag = ledger.success_etag_by_key.get(obj.key)
    if success_etag is None:
        return True
    return success_etag != obj.etag


def _load_ledger_state(
    spark_session: SparkSession, full_ledger_table: str
) -> LedgerState:
    if not spark_session.catalog.tableExists(full_ledger_table):
        return LedgerState(
            success_etag_by_key={},
            failed_keys=set(),
            incremental_watermark_unix=None,
        )

    # Fine for hundreds/thousands of ledger rows; if this grows large over years,
    # replace with Spark-side aggregation instead of driver collect().
    rows = (
        spark_session.table(full_ledger_table)
        .select("s3_key", "etag", "status")
        .collect()
    )

    success_etag_by_key: Dict[str, str] = {}
    failed_keys: Set[str] = set()
    incremental_watermark_unix: Optional[int] = None

    for row in rows:
        key = row.s3_key
        etag = row.etag or ""
        if row.status == "failed":
            failed_keys.add(key)
            continue
        if row.status != "success":
            continue
        success_etag_by_key[key] = etag
        unix = _incremental_unix(key)
        if unix is not None and (
            incremental_watermark_unix is None or unix > incremental_watermark_unix
        ):
            incremental_watermark_unix = unix

    return LedgerState(
        success_etag_by_key=success_etag_by_key,
        failed_keys=failed_keys,
        incremental_watermark_unix=incremental_watermark_unix,
    )


def _bootstrap_empty_tables(
    spark_session: SparkSession,
    full_messages_table: str,
    messages_path: str,
    full_ledger_table: str,
    ledger_path: str,
    partition_cols: List[str],
) -> None:
    loader = DeltaLoader()
    if not spark_session.catalog.tableExists(full_messages_table):
        loader.load_table(
            table_name=full_messages_table,
            path=messages_path,
            source_df=_empty_messages_df(spark_session),
            partition_by=partition_cols,
            merge_on=MERGE_ON,
            when_matched_update_condition="FALSE",
        )
    if not spark_session.catalog.tableExists(full_ledger_table):
        loader.load_table(
            table_name=full_ledger_table,
            path=ledger_path,
            source_df=_empty_ledger_df(spark_session),
            merge_on=LEDGER_MERGE_ON,
            when_matched_update_condition="source.ts_load >= target.ts_load",
        )


def _ingest_file(
    obj: S3ObjectRef,
    loader: DeltaLoader,
    full_messages_table: str,
    messages_path: str,
    partition_cols: List[str],
) -> int:
    raw_df = spark.read.format("json").option("multiLine", "false").load(obj.uri)
    enriched = _enrich_file_df(raw_df, obj)
    row_count = enriched.count()
    if row_count == 0:
        logger.warning(f"m=_ingest_file, s3_key={obj.key}, msg=No valid rows in file")
        return 0

    loader.load_table(
        table_name=full_messages_table,
        path=messages_path,
        source_df=enriched,
        partition_by=partition_cols,
        merge_on=MERGE_ON,
        when_matched_update_condition="FALSE",
    )
    return row_count


def _upsert_ledger_row(
    loader: DeltaLoader,
    full_ledger_table: str,
    ledger_path: str,
    obj: S3ObjectRef,
    dag_run_id: str,
    status: str,
    row_count: int,
) -> None:
    # Column order: natural key → id → characteristics → metrics → timestamp.
    ledger_df = spark.createDataFrame(
        [
            (
                obj.key,
                dag_run_id,
                obj.bucket,
                obj.etag,
                status,
                obj.size_bytes,
                row_count,
            )
        ],
        schema=StructType(
            [
                StructField("s3_key", StringType(), False),
                StructField("id_dag_run", StringType(), True),
                StructField("s3_bucket", StringType(), False),
                StructField("etag", StringType(), True),
                StructField("status", StringType(), False),
                StructField("size_bytes", LongType(), True),
                StructField("row_count", LongType(), True),
            ]
        ),
    ).withColumn("ts_load", F.current_timestamp())

    loader.load_table(
        table_name=full_ledger_table,
        path=ledger_path,
        source_df=ledger_df,
        merge_on=LEDGER_MERGE_ON,
        when_matched_update_condition="source.ts_load >= target.ts_load",
    )


def _enrich_file_df(df: DataFrame, obj: S3ObjectRef) -> DataFrame:
    expected_source = _expected_source(obj.key)
    for column_name in MESSAGE_COLUMNS:
        if column_name == "tunnel_id":
            continue
        if column_name not in df.columns:
            if column_name in ("year", "month", "day"):
                df = df.withColumn(column_name, F.lit(None).cast(IntegerType()))
            else:
                df = df.withColumn(column_name, F.lit(None).cast(StringType()))

    df = _normalize_id_tunnel(df)

    id_run = _backfill_run_id(obj.key) or (
        str(_incremental_unix(obj.key)) if _incremental_unix(obj.key) else ""
    )

    df = (
        df.withColumn("s3_key", F.lit(obj.key))
        .withColumn("s3_bucket", F.lit(obj.bucket))
        .withColumn("id_run", F.lit(id_run))
        .withColumn(
            "source",
            F.when(
                F.col("source").isNull() | (F.trim(F.col("source")) == ""),
                F.lit(expected_source),
            ).otherwise(F.col("source")),
        )
        .withColumn("ts_created", F.to_timestamp("ts_created"))
        .withColumn("ts_load", F.current_timestamp())
        .withColumn(
            "year",
            F.coalesce(F.col("year").cast(IntegerType()), F.year("ts_created")),
        )
        .withColumn(
            "month",
            F.coalesce(F.col("month").cast(IntegerType()), F.month("ts_created")),
        )
        .withColumn(
            "day",
            F.coalesce(F.col("day").cast(IntegerType()), F.dayofmonth("ts_created")),
        )
    )

    # IDs → characteristics → timestamps → partitions (naming conventions).
    # Reject source/prefix mismatches without an extra count() action.
    return (
        df.filter(F.col("source") == F.lit(expected_source))
        .filter(F.col("id_message").isNotNull())
        .filter(F.trim(F.col("id_message")) != "")
        .select(
            "id_message",
            "id_lead",
            "id_crm",
            "id_tunnel",
            "id_run",
            "whatsapp_identity",
            "host_name",
            "role",
            "content",
            "source",
            "s3_key",
            "s3_bucket",
            "ts_created",
            "ts_load",
            "year",
            "month",
            "day",
        )
    )


def _normalize_id_tunnel(df: DataFrame) -> DataFrame:
    """Land producer tunnel_id as id_tunnel; tolerate either name from the file."""
    has_tunnel_id = "tunnel_id" in df.columns
    has_id_tunnel = "id_tunnel" in df.columns
    if has_tunnel_id and not has_id_tunnel:
        return df.withColumnRenamed("tunnel_id", "id_tunnel")
    if has_tunnel_id and has_id_tunnel:
        return df.withColumn(
            "id_tunnel", F.coalesce(F.col("id_tunnel"), F.col("tunnel_id"))
        ).drop("tunnel_id")
    if not has_id_tunnel:
        return df.withColumn("id_tunnel", F.lit(None).cast(StringType()))
    return df


def _expected_source(s3_key: str) -> str:
    if "/backfill/" in s3_key:
        return BACKFILL_SOURCE
    if "/incremental/" in s3_key:
        return INCREMENTAL_SOURCE
    raise ValueError(f"Cannot infer source family for s3_key={s3_key}")


def _backfill_run_id(s3_key: str) -> Optional[str]:
    match = BACKFILL_RUN_ID_RE.search(s3_key)
    return match.group(1) if match else None


def _incremental_unix(s3_key: str) -> Optional[int]:
    match = INCREMENTAL_UNIX_RE.search(s3_key)
    return int(match.group(1)) if match else None


def _list_s3_objects(
    bucket: str,
    prefix: str,
    start_after: Optional[str],
    suffix: str,
) -> List[S3ObjectRef]:
    client = boto3.client("s3")
    paginator = client.get_paginator("list_objects_v2")
    kwargs: dict = {"Bucket": bucket, "Prefix": prefix}
    if start_after:
        kwargs["StartAfter"] = start_after

    refs: List[S3ObjectRef] = []
    for page in paginator.paginate(**kwargs):
        for item in page.get("Contents", []):
            key = item["Key"]
            if not key.endswith(suffix):
                continue
            etag = (item.get("ETag") or "").strip('"')
            refs.append(
                S3ObjectRef(
                    uri=f"s3://{bucket}/{key}",
                    bucket=bucket,
                    key=key,
                    etag=etag,
                    size_bytes=int(item.get("Size") or 0),
                )
            )
    return refs


def _head_object(bucket: str, key: str) -> S3ObjectRef:
    client = boto3.client("s3")
    response = client.head_object(Bucket=bucket, Key=key)
    etag = (response.get("ETag") or "").strip('"')
    return S3ObjectRef(
        uri=f"s3://{bucket}/{key}",
        bucket=bucket,
        key=key,
        etag=etag,
        size_bytes=int(response.get("ContentLength") or 0),
    )


def _is_message_object(s3_key: str) -> bool:
    basename = s3_key.rsplit("/", 1)[-1]
    if basename in ("done.jsonl", "errors.jsonl", "_SUCCESS", "watermark.json"):
        return False
    if basename.endswith(".errors.jsonl"):
        return False
    if "/backfill/" in s3_key:
        return basename.startswith("batch_") and basename.endswith(".jsonl")
    if "/incremental/" in s3_key:
        return basename.endswith(".jsonl") and not basename.endswith(".errors.jsonl")
    return False


def _parse_s3_uri(uri: str) -> Tuple[str, str]:
    path = uri.split("://", 1)[-1]
    bucket, _, key = path.partition("/")
    return bucket, key


def _empty_messages_df(spark_session: SparkSession) -> DataFrame:
    return spark_session.createDataFrame([], _messages_schema())


def _empty_ledger_df(spark_session: SparkSession) -> DataFrame:
    return spark_session.createDataFrame([], _ledger_schema())


def _messages_schema() -> StructType:
    return StructType(
        [
            StructField("id_message", StringType(), True),
            StructField("id_lead", StringType(), True),
            StructField("id_crm", StringType(), True),
            StructField("id_tunnel", StringType(), True),
            StructField("id_run", StringType(), True),
            StructField("whatsapp_identity", StringType(), True),
            StructField("host_name", StringType(), True),
            StructField("role", StringType(), True),
            StructField("content", StringType(), True),
            StructField("source", StringType(), True),
            StructField("s3_key", StringType(), True),
            StructField("s3_bucket", StringType(), True),
            StructField("ts_created", TimestampType(), True),
            StructField("ts_load", TimestampType(), True),
            StructField("year", IntegerType(), True),
            StructField("month", IntegerType(), True),
            StructField("day", IntegerType(), True),
        ]
    )


def _ledger_schema() -> StructType:
    return StructType(
        [
            StructField("s3_key", StringType(), False),
            StructField("id_dag_run", StringType(), True),
            StructField("s3_bucket", StringType(), False),
            StructField("etag", StringType(), True),
            StructField("status", StringType(), False),
            StructField("size_bytes", LongType(), True),
            StructField("row_count", LongType(), True),
            StructField("ts_load", TimestampType(), True),
        ]
    )


if __name__ == "__main__":
    main()
