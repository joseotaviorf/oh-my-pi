"""PySpark job: validate transpiled SQL syntax on a real Spark cluster.

Reads SQL files from S3, runs EXPLAIN on each to validate syntax without
executing the full query. Writes results JSON to S3.

Usage (via emr-cli):
  emr-cli transient \
    --uri s3://artifacts.s3.data.quintoandar.com.br/emr/staging/syntax-test/syntax_test_job.py \
    --name "syntax-validation" \
    --step-name "Validate transpiled SQL" \
    --wait --follow-logs \
    -- --sql-prefix s3://artifacts.s3.data.quintoandar.com.br/emr/staging/syntax-test/sql/ \
       --result-uri s3://artifacts.s3.data.quintoandar.com.br/emr/staging/syntax-test/results.json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import traceback
from typing import Any
from urllib.parse import urlparse

import boto3
from pyspark.sql import SparkSession

_TEMPLATE_RE = re.compile(r"\{([a-z_][a-z0-9_]*)\}")


def _substitute_templates(sql: str) -> str:
    clean = sql.replace("{{", "").replace("}}", "")
    return _TEMPLATE_RE.sub("'__placeholder__'", clean)


def split_s3_uri(uri: str) -> tuple[str, str]:
    parsed = urlparse(uri)
    return parsed.netloc, parsed.path.lstrip("/")


def list_sql_files(s3_client, bucket: str, prefix: str) -> list[str]:
    keys: list[str] = []
    paginator = s3_client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            if obj["Key"].endswith(".sql"):
                keys.append(obj["Key"])
    return sorted(keys)


def read_s3_text(s3_client, bucket: str, key: str) -> str:
    response = s3_client.get_object(Bucket=bucket, Key=key)
    return response["Body"].read().decode("utf-8")


def write_s3_json(s3_client, uri: str, payload: Any) -> None:
    bucket, key = split_s3_uri(uri)
    s3_client.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(payload, default=str, indent=2).encode("utf-8"),
        ContentType="application/json",
    )


def validate_sql(spark: SparkSession, sql: str) -> tuple[bool, str | None]:
    substituted = _substitute_templates(sql)
    if not substituted.strip():
        return False, "Empty SQL after template substitution"
    try:
        spark._jsparkSession.sessionState().sqlParser().parsePlan(substituted)
        return True, None
    except Exception as exc:
        return False, str(exc)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate transpiled SQL syntax on a real Spark cluster"
    )
    parser.add_argument(
        "--sql-prefix",
        required=True,
        help="S3 prefix containing SQL files (e.g., s3://bucket/prefix/)",
    )
    parser.add_argument(
        "--result-uri",
        required=True,
        help="S3 URI to write results JSON",
    )
    args = parser.parse_args()

    bucket, prefix = split_s3_uri(args.sql_prefix)
    if not prefix.endswith("/"):
        prefix += "/"
    s3 = boto3.client("s3")

    sql_keys = list_sql_files(s3, bucket, prefix)
    print(f"Found {len(sql_keys)} SQL files to validate")

    spark = SparkSession.builder.appName("SyntaxValidation").getOrCreate()

    results: list[dict[str, Any]] = []
    passed = failed = 0

    try:
        for i, key in enumerate(sql_keys):
            rel_path = key[len(prefix) :].lstrip("/")
            parts = rel_path.split("/")
            scope_id = parts[0] if parts else "unknown"
            table_name = parts[-1].replace(".sql", "") if parts else "unknown"

            try:
                sql = read_s3_text(s3, bucket, key)
                valid, error = validate_sql(spark, sql)
            except Exception:
                valid = False
                error = f"Failed to read/validate: {traceback.format_exc()}"

            result = {
                "scope_id": scope_id,
                "table_name": table_name,
                "s3_key": key,
                "valid": valid,
                "error": error,
            }
            results.append(result)

            if valid:
                passed += 1
            else:
                failed += 1
                print(f"  FAIL [{scope_id}] {table_name}: {error[:200]}")

            if (i + 1) % 50 == 0:
                print(
                    f"  Progress: {i + 1}/{len(sql_keys)} ({passed} pass, {failed} fail)"
                )

    finally:
        spark.stop()

    summary = {
        "total": len(results),
        "passed": passed,
        "failed": failed,
        "pass_rate": f"{passed / max(len(results), 1) * 100:.1f}%",
        "results": results,
    }
    write_s3_json(s3, args.result_uri, summary)
    print(f"\nDone: {passed} passed, {failed} failed out of {len(results)} files")
    print(f"Results written to {args.result_uri}")

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
