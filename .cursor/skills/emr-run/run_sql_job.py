"""EMR PySpark job: run staged SQL statements and emit a JSON result to S3.

Generic ad-hoc runner for the ``emr-run`` skill (not migration validation).
Reads a SQL file from S3 (one or more statements separated by ``;``), executes
them in order, collects up to ``--limit`` rows from the LAST statement, prints
them to stdout (visible via ``--follow-logs``) and writes the JSON payload to
``--result-s3-uri`` (fetched via ``--wait-result``).
"""

from __future__ import annotations

import argparse
import json
import re
import time
from typing import Any
from urllib.parse import urlparse

import boto3
from pyspark.sql import SparkSession


def create_adhoc_spark_session(app_name: str = "EmrRunSqlJob") -> SparkSession:
    """Glue Hive metastore + Delta — mirrors bietlejuice ``create_emr_spark_session``."""
    return (
        SparkSession.builder.appName(app_name)
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
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


def fetch_text_from_s3(s3_uri: str) -> str:
    bucket, key = split_s3_uri(s3_uri)
    response = boto3.client("s3").get_object(Bucket=bucket, Key=key)
    return response["Body"].read().decode("utf-8")


def write_result_to_s3(result_s3_uri: str, payload: dict[str, Any]) -> None:
    bucket, key = split_s3_uri(result_s3_uri)
    boto3.client("s3").put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(payload, default=str).encode("utf-8"),
        ContentType="application/json",
    )


def _has_executable_sql(statement: str) -> bool:
    """False for fragments that are only comments/whitespace (Spark parse-fails on them)."""
    without_blocks = re.sub(r"/\*.*?\*/", "", statement, flags=re.S)
    lines = (re.sub(r"--.*", "", line) for line in without_blocks.splitlines())
    return any(line.strip() for line in lines)


def split_statements(sql_text: str) -> list[str]:
    """Split on ``;`` outside quoted strings and ``--`` / ``/* */`` comments.

    Comment-only fragments (e.g. a trailing ``-- note`` after the last ``;``)
    are dropped instead of being handed to ``spark.sql``.
    """
    statements: list[str] = []
    current: list[str] = []
    in_single = in_double = in_line_comment = in_block_comment = False
    idx = 0
    while idx < len(sql_text):
        char = sql_text[idx]
        nxt = sql_text[idx + 1] if idx + 1 < len(sql_text) else ""
        if in_line_comment:
            current.append(char)
            if char == "\n":
                in_line_comment = False
        elif in_block_comment:
            current.append(char)
            if char == "*" and nxt == "/":
                current.append(nxt)
                idx += 1
                in_block_comment = False
        elif in_single:
            current.append(char)
            if char == "'" and nxt == "'":
                current.append(nxt)
                idx += 1
            elif char == "'":
                in_single = False
        elif in_double:
            current.append(char)
            if char == '"':
                in_double = False
        elif char == "-" and nxt == "-":
            current.append(char)
            in_line_comment = True
        elif char == "/" and nxt == "*":
            current.append(char)
            in_block_comment = True
        elif char == "'":
            current.append(char)
            in_single = True
        elif char == '"':
            current.append(char)
            in_double = True
        elif char == ";":
            statements.append("".join(current))
            current = []
        else:
            current.append(char)
        idx += 1
    statements.append("".join(current))
    return [
        stmt
        for stmt in (fragment.strip() for fragment in statements)
        if stmt and _has_executable_sql(stmt)
    ]


def normalize_value(value: Any) -> Any:
    if value is None or isinstance(value, (int, float, bool)):
        return value
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sql-s3-uri", required=True)
    parser.add_argument("--result-s3-uri", required=True)
    parser.add_argument("--limit", type=int, default=1000)
    parser.add_argument("--show-rows", type=int, default=50)
    args = parser.parse_args()

    spark = create_adhoc_spark_session()
    payload: dict[str, Any] = {
        "statements": 0,
        "schema": [],
        "rows": [],
        "row_count": 0,
        "truncated": False,
        "duration_sec": 0.0,
    }
    started = time.time()

    try:
        statements = split_statements(fetch_text_from_s3(args.sql_s3_uri))
        payload["statements"] = len(statements)
        result_df = None
        for position, statement in enumerate(statements, start=1):
            print(f"=== statement {position}/{len(statements)} ===")
            result_df = spark.sql(statement)

        if result_df is not None and result_df.columns:
            payload["schema"] = [
                [field.name, field.dataType.simpleString()]
                for field in result_df.schema.fields
            ]
            collected = result_df.limit(args.limit + 1).collect()
            payload["truncated"] = len(collected) > args.limit
            collected = collected[: args.limit]
            columns = result_df.columns
            payload["rows"] = [
                {col: normalize_value(row[col]) for col in columns} for row in collected
            ]
            payload["row_count"] = len(payload["rows"])
            preview = (
                spark.createDataFrame(collected, result_df.schema)
                if collected
                else result_df
            )
            preview.show(n=min(args.show_rows, args.limit), truncate=False)
    except Exception as exc:  # noqa: BLE001 — report any Spark/SQL failure in the result
        payload["error"] = str(exc)
        print(f"ERROR: {exc}")
    finally:
        payload["duration_sec"] = round(time.time() - started, 1)
        spark.stop()

    write_result_to_s3(args.result_s3_uri, payload)


if __name__ == "__main__":
    main()
