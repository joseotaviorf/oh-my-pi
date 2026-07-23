"""PySpark job: execute SQL query and capture count + schema + profile to S3.

Used by both the Twin (Databricks) and Migration (EMR) validation DAGs.
Each task runs this job with a single query, writes metrics as JSON to S3.
Profile includes null counts and xxhash64 checksums per column.
"""

from __future__ import annotations

import argparse
import json
import re
from typing import Any, List, Tuple
from urllib.parse import urlparse

import boto3
from pyspark.sql import SparkSession

MAX_PROFILE_COLUMNS = 120
MIG_NULL_SENTINEL = "__MIG_NULL__"
_COMPLEX_TYPE_PREFIXES = ("array<", "map<", "struct<")
_FLOAT_TYPES = frozenset({"float", "double", "real"})
_INTEGER_TYPES = frozenset(
    {"tinyint", "smallint", "int", "integer", "bigint", "long", "short", "byte"}
)
_DECIMAL_RE = re.compile(r"^decimal\s*\(", re.IGNORECASE)
_TIMESTAMP_TYPES = frozenset({"timestamp", "timestamp_ntz", "date"})
_CHECKSUM_SKIP_DEFAULT = frozenset(
    {"ts_load", "op_cdc", "ts_cdc_transaction", "ts_database_transaction"}
)


def _normalize_type_name(type_name: str) -> str:
    return type_name.lower().replace(" ", "").strip('"')


def _is_profileable(type_name: str) -> bool:
    normalized = _normalize_type_name(type_name)
    if any(normalized.startswith(p) for p in _COMPLEX_TYPE_PREFIXES):
        return False
    return normalized != "binary"


def _normalize_col_for_hash(col_ref: str, type_name: str) -> str:
    normalized = _normalize_type_name(type_name)
    if normalized in _TIMESTAMP_TYPES:
        if normalized == "date":
            return f"DATE_FORMAT({col_ref}, 'yyyy-MM-dd')"
        return (
            f"DATE_FORMAT(CAST({col_ref} AS TIMESTAMP), 'yyyy-MM-dd HH:mm:ss.SSSSSS')"
        )
    if normalized in _FLOAT_TYPES:
        return f"CAST(CAST({col_ref} AS DECIMAL(38, 18)) AS STRING)"
    return f"CAST({col_ref} AS STRING)"


def _hash_expression(name: str, type_name: str) -> str:
    col_ref = f"t.`{name}`"
    normalized = _normalize_col_for_hash(col_ref, type_name)
    return f"xxhash64(COALESCE({normalized}, '{MIG_NULL_SENTINEL}'))"


def build_profile_query(
    sql: str, schema: List[List[str]]
) -> Tuple[str, dict[str, Any]]:
    """Build a single-pass profile query with null counts and checksums."""
    checksum_skip = {n.lower() for n in _CHECKSUM_SKIP_DEFAULT}
    profileable = []
    skipped = []

    for entry in schema:
        if len(entry) < 2:
            continue
        name, type_name = str(entry[0]), str(entry[1])
        if not _is_profileable(type_name):
            skipped.append(name)
            continue
        profileable.append((name, type_name))

    truncated = []
    if len(profileable) > MAX_PROFILE_COLUMNS:
        truncated = [n for n, _ in profileable[MAX_PROFILE_COLUMNS:]]
        profileable = profileable[:MAX_PROFILE_COLUMNS]

    inner_projections = []
    outer_select = ["COUNT(*) AS cnt"]

    for name, type_name in profileable:
        inner_projections.append(f"t.`{name}`")
        hash_alias = f"h_{name}"
        inner_projections.append(
            f"{_hash_expression(name, type_name)} AS `{hash_alias}`"
        )
        outer_select.append(f"COUNT_IF(`{name}` IS NULL) AS `null_{name}`")
        if name.lower() not in checksum_skip:
            sum_expr = f"SUM(CAST(`{hash_alias}` AS DECIMAL(38, 0)))"
            outer_select.append(f"CAST({sum_expr} AS STRING) AS `chk_sum_{name}`")
            outer_select.append(
                f"SUBSTR(SHA2(CAST({sum_expr} AS STRING), 256), 1, 32) AS `chk_{name}`"
            )

    inner_sql = ",\n    ".join(inner_projections)
    outer_sql = ",\n  ".join(outer_select)
    query = (
        f"SELECT\n  {outer_sql}\n"
        f"FROM (\n"
        f"  SELECT\n    {inner_sql}\n"
        f"  FROM ({sql}) AS t\n"
        f") AS hashed"
    )
    metadata = {
        "columns": [n for n, _ in profileable],
        "skipped_columns": skipped,
        "truncated_columns": truncated,
        "checksum_skipped": [n for n, _ in profileable if n.lower() in checksum_skip],
    }
    return query, metadata


def parse_profile_row(row: dict[str, Any], metadata: dict[str, Any]) -> dict[str, Any]:
    checksum_skip = {n.lower() for n in metadata.get("checksum_skipped", [])}
    columns = {}
    for col_name in metadata.get("columns", []):
        null_key = f"null_{col_name}"
        null_count = int(row.get(null_key, row.get(f"`{null_key}`", 0)) or 0)
        checksum = None
        checksum_sum = None
        if col_name.lower() not in checksum_skip:
            chk_key = f"chk_{col_name}"
            sum_key = f"chk_sum_{col_name}"
            raw_chk = row.get(chk_key, row.get(f"`{chk_key}`"))
            raw_sum = row.get(sum_key, row.get(f"`{sum_key}`"))
            checksum = str(raw_chk).strip() if raw_chk is not None else None
            checksum_sum = str(raw_sum).strip() if raw_sum is not None else None
        columns[col_name] = {
            "null_count": null_count,
            "checksum": checksum,
            "checksum_sum": checksum_sum,
        }
    return {
        "columns": columns,
        "skipped_columns": metadata.get("skipped_columns", []),
        "truncated_columns": metadata.get("truncated_columns", []),
    }


def create_spark_session(
    runtime: str, app_name: str = "MigrationMetricCapture"
) -> SparkSession:
    builder = SparkSession.builder.appName(app_name)
    if runtime == "emr":
        builder = (
            builder.config(
                "spark.sql.extensions",
                "io.delta.sql.DeltaSparkSessionExtension",
            )
            .config(
                "spark.sql.catalog.spark_catalog",
                "org.apache.spark.sql.delta.catalog.DeltaCatalog",
            )
            .config("spark.sql.catalogImplementation", "hive")
            .config("spark.hadoop.fs.s3a.acl.default", "BucketOwnerFullControl")
            .config("spark.hadoop.fs.s3a.canned.acl", "BucketOwnerFullControl")
        )
    builder = builder.enableHiveSupport()
    return builder.getOrCreate()


def split_s3_uri(uri: str) -> tuple[str, str]:
    parsed = urlparse(uri)
    return parsed.netloc, parsed.path.lstrip("/")


def read_s3_text(uri: str) -> str:
    bucket, key = split_s3_uri(uri)
    client = boto3.client("s3")
    response = client.get_object(Bucket=bucket, Key=key)
    return response["Body"].read().decode("utf-8")


def write_s3_json(uri: str, payload: dict[str, Any]) -> None:
    bucket, key = split_s3_uri(uri)
    client = boto3.client("s3")
    client.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(payload, default=str).encode("utf-8"),
        ContentType="application/json",
    )


def capture_metrics(
    spark: SparkSession, sql: str, *, skip_profile: bool = False
) -> dict[str, Any]:
    """Execute SQL and return count + schema + profile as a dict."""
    payload: dict[str, Any] = {
        "schema": [],
        "count": 0,
        "profile": None,
        "error": None,
    }

    try:
        describe_df = spark.sql(f"DESCRIBE ({sql})")
        schema = []
        for row in describe_df.collect():
            row_dict = row.asDict()
            col_name = row_dict.get("col_name")
            data_type = row_dict.get("data_type")
            if not col_name or str(col_name).startswith("#"):
                continue
            schema.append([str(col_name), str(data_type)])
        payload["schema"] = schema

        if skip_profile:
            count_df = spark.sql(f"SELECT COUNT(*) AS cnt FROM ({sql}) AS t")
            payload["count"] = int(count_df.collect()[0]["cnt"])
        else:
            profile_query, profile_meta = build_profile_query(sql, schema)
            profile_df = spark.sql(profile_query)
            profile_row = profile_df.collect()[0].asDict()
            payload["count"] = int(profile_row.get("cnt", 0))
            payload["profile"] = parse_profile_row(profile_row, profile_meta)
    except Exception as exc:
        payload["error"] = str(exc)

    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sql-s3-uri", required=True, help="S3 URI of the SQL file")
    parser.add_argument(
        "--result-s3-uri", required=True, help="S3 URI to write metric JSON"
    )
    parser.add_argument("--run-id", required=True, help="Migration run identifier")
    parser.add_argument("--runtime", required=True, choices=["databricks", "emr"])
    parser.add_argument("--domain", required=True)
    parser.add_argument("--dag-name", required=True)
    parser.add_argument("--table-name", required=True)
    parser.add_argument(
        "--skip-profile",
        action="store_true",
        help="Skip null count and checksum profile",
    )
    args = parser.parse_args()

    spark = create_spark_session(args.runtime)
    try:
        sql = read_s3_text(args.sql_s3_uri)
        payload = capture_metrics(spark, sql, skip_profile=args.skip_profile)
        payload.update(
            {
                "run_id": args.run_id,
                "runtime": args.runtime,
                "domain": args.domain,
                "dag_name": args.dag_name,
                "table_name": args.table_name,
                "version": 1,
            }
        )
        write_s3_json(args.result_s3_uri, payload)
        if payload.get("error"):
            print(f"WARNING: capture error recorded: {payload['error']}")
            print("Continuing so comparison DAG can emit a FAIL verdict.")
    finally:
        if args.runtime == "emr":
            spark.stop()


if __name__ == "__main__":
    main()
