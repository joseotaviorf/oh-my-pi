"""EMR PySpark job: execute staged SQL and emit validation JSON to S3."""

from __future__ import annotations

import argparse
import json
import re
from typing import Any
from urllib.parse import urlparse

import boto3
from pyspark.sql import SparkSession

# Keep profile SQL generation in sync with
# .cursor/skills/databricks-emr-migration/profile.py

PROFILE_VERSION = 1
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


def create_migration_validate_spark_session(app_name: str = "MigrationValidateJob") -> SparkSession:
    """Glue Hive metastore + Delta — mirrors bietlejuice ``create_emr_spark_session``."""
    return (
        SparkSession.builder.appName(app_name)
        .config(
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
        .enableHiveSupport()
        .getOrCreate()
    )


def split_s3_uri(uri: str) -> tuple[str, str]:
    parsed = urlparse(uri)
    return parsed.netloc, parsed.path.lstrip("/")


def fetch_sql_from_s3(sql_s3_uri: str) -> str:
    bucket, key = split_s3_uri(sql_s3_uri)
    client = boto3.client("s3")
    response = client.get_object(Bucket=bucket, Key=key)
    return response["Body"].read().decode("utf-8")


def write_result_to_s3(result_s3_uri: str, payload: dict[str, Any]) -> None:
    bucket, key = split_s3_uri(result_s3_uri)
    client = boto3.client("s3")
    client.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(payload, default=str).encode("utf-8"),
        ContentType="application/json",
    )


def normalize_value(value: Any) -> Any:
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return value.isoformat()
    if isinstance(value, (int, float, bool)):
        return value
    return str(value)


def row_to_dict(row, columns: list[str]) -> dict[str, Any]:
    if hasattr(row, "asDict"):
        raw = row.asDict(recursive=True)
        return {key: normalize_value(raw.get(key)) for key in columns}
    return {columns[idx]: normalize_value(row[idx]) for idx in range(len(columns))}


def _normalize_type_name(type_name: str) -> str:
    return type_name.lower().replace(" ", "").strip('"')


def is_profileable_type(type_name: str) -> bool:
    normalized = _normalize_type_name(type_name)
    if any(normalized.startswith(prefix) for prefix in _COMPLEX_TYPE_PREFIXES):
        return False
    if normalized in {"binary"}:
        return False
    return True


def normalize_for_hash(column: str, type_name: str) -> str:
    return _normalize_col_for_hash(f"`{column}`", type_name)


def _normalize_col_for_hash(col_ref: str, type_name: str) -> str:
    normalized = _normalize_type_name(type_name)
    if normalized in _TIMESTAMP_TYPES:
        if normalized == "date":
            return f"DATE_FORMAT({col_ref}, 'yyyy-MM-dd')"
        return (
            f"DATE_FORMAT(CAST({col_ref} AS TIMESTAMP), "
            f"'yyyy-MM-dd HH:mm:ss.SSSSSS')"
        )
    if normalized in _FLOAT_TYPES:
        return f"CAST(CAST({col_ref} AS DECIMAL(38, 18)) AS STRING)"
    if normalized in _INTEGER_TYPES or _DECIMAL_RE.match(normalized):
        return f"CAST({col_ref} AS STRING)"
    if normalized in {"boolean", "bool"}:
        return f"CAST({col_ref} AS STRING)"
    return f"CAST({col_ref} AS STRING)"


def _hash_expression(name: str, type_name: str, *, table_alias: str = "t") -> str:
    col_ref = f"{table_alias}.`{name}`"
    normalized = _normalize_col_for_hash(col_ref, type_name)
    return f"xxhash64(COALESCE({normalized}, '{MIG_NULL_SENTINEL}'))"


def build_profile_query(
    pinned_sql: str,
    schema: list[list[str]],
    *,
    checksum_skipped: frozenset[str] | set[str] | None = None,
) -> tuple[str, dict[str, Any]]:
    checksum_skip = {name.lower() for name in (checksum_skipped or _CHECKSUM_SKIP_DEFAULT)}
    skipped: list[str] = []
    profileable: list[tuple[str, str]] = []
    for entry in schema:
        if len(entry) < 2:
            continue
        name, type_name = str(entry[0]), str(entry[1])
        if not is_profileable_type(type_name):
            skipped.append(name)
            continue
        profileable.append((name, type_name))

    truncated: list[str] = []
    if len(profileable) > MAX_PROFILE_COLUMNS:
        truncated = [name for name, _ in profileable[MAX_PROFILE_COLUMNS:]]
        profileable = profileable[:MAX_PROFILE_COLUMNS]

    checksum_skipped_columns = [
        name for name, _ in profileable if name.lower() in checksum_skip
    ]

    inner_projections: list[str] = []
    outer_select = ["COUNT(*) AS cnt"]
    column_names = [name for name, _ in profileable]

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
        f"  FROM ({pinned_sql}) AS t\n"
        f") AS hashed"
    )
    metadata = {
        "version": PROFILE_VERSION,
        "columns": {name: {} for name in column_names},
        "skipped_columns": skipped,
        "truncated_columns": truncated,
        "checksum_skipped_columns": checksum_skipped_columns,
    }
    return query, metadata


def parse_profile_from_row(row: dict[str, Any], metadata: dict[str, Any]) -> dict[str, Any]:
    checksum_skip = {name.lower() for name in metadata.get("checksum_skipped_columns", [])}
    columns: dict[str, Any] = {}
    for col_name in metadata.get("columns", {}):
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
        "version": metadata.get("version", PROFILE_VERSION),
        "columns": columns,
        "skipped_columns": list(metadata.get("skipped_columns", [])),
        "truncated_columns": list(metadata.get("truncated_columns", [])),
        "checksum_skipped_columns": list(metadata.get("checksum_skipped_columns", [])),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sql-s3-uri", required=True)
    parser.add_argument("--result-s3-uri", required=True)
    parser.add_argument("--order-by", default="1,2,3")
    parser.add_argument("--sample-limit", type=int, default=100)
    parser.add_argument("--skip-sample", action="store_true")
    parser.add_argument("--skip-profile", action="store_true")
    args = parser.parse_args()

    spark = create_migration_validate_spark_session()
    payload: dict[str, Any] = {"schema": [], "count": 0, "sample": []}

    try:
        sql_text = fetch_sql_from_s3(args.sql_s3_uri)

        describe_df = spark.sql(f"DESCRIBE ({sql_text})")
        schema = []
        for row in describe_df.collect():
            row_dict = row_to_dict(row, describe_df.columns)
            col_name = row_dict.get("col_name")
            data_type = row_dict.get("data_type")
            if not col_name or str(col_name).startswith("#"):
                continue
            schema.append([str(col_name), str(data_type)])
        payload["schema"] = schema

        if args.skip_profile:
            count_df = spark.sql(f"SELECT COUNT(*) AS cnt FROM ({sql_text}) AS t")
            payload["count"] = int(count_df.collect()[0]["cnt"])
        else:
            profile_query, profile_shell = build_profile_query(sql_text, schema)
            profile_df = spark.sql(profile_query)
            profile_row = row_to_dict(profile_df.collect()[0], profile_df.columns)
            payload["count"] = int(profile_row.get("cnt", 0))
            payload["profile"] = parse_profile_from_row(profile_row, profile_shell)

        if not args.skip_sample:
            order_by = args.order_by.strip()
            sample_df = spark.sql(
                f"SELECT * FROM ({sql_text}) AS t ORDER BY {order_by} "
                f"LIMIT {args.sample_limit}"
            )
            columns = sample_df.columns
            payload["sample"] = [
                row_to_dict(row, columns) for row in sample_df.collect()
            ]
    except Exception as exc:
        payload["error"] = str(exc)
    finally:
        spark.stop()

    write_result_to_s3(args.result_s3_uri, payload)


if __name__ == "__main__":
    main()
