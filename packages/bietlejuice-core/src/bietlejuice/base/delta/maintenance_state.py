"""S3 markers for daily Delta table maintenance (VACUUM / OPTIMIZE) idempotency.

Markers are stored in the artifacts bucket (not the datalake data bucket)::

    s3://{artifacts_bucket}/{state_prefix}/{environment}/{table_slug}/{YYYY-MM-DD}.json

``state_prefix`` and ``region_name`` must be supplied by the caller (typically via
``ConfigurationService``).
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Dict, Optional, Tuple

import boto3
from botocore.exceptions import ClientError


def slugify_full_table_name(full_table_name: str) -> str:
    """Turn ``database.table`` into a safe S3 path segment."""
    return full_table_name.replace(".", "__")


def normalize_s3_bucket(bucket_or_uri: str) -> str:
    """Return the bucket name from ``bucket`` or ``s3://bucket/...``."""
    value = bucket_or_uri.strip()
    if value.startswith("s3://"):
        value = value[5:]
    return value.split("/", 1)[0]


def build_marker_key(
    environment: str,
    full_table_name: str,
    maintenance_date: str,
    state_prefix: str,
) -> str:
    """Build the S3 object key (without bucket) for a maintenance marker."""
    prefix = state_prefix.strip("/")
    table_slug = slugify_full_table_name(full_table_name)
    return f"{prefix}/{environment}/{table_slug}/{maintenance_date}.json"


def read_maintenance_marker(
    bucket: str,
    key: str,
    region_name: str,
) -> Optional[Dict[str, Any]]:
    """Return marker payload if the object exists, else ``None``."""
    s3_client = boto3.client("s3", region_name=region_name)
    try:
        response = s3_client.get_object(Bucket=normalize_s3_bucket(bucket), Key=key)
    except ClientError as exc:
        error_code = exc.response.get("Error", {}).get("Code", "")
        if error_code in ("404", "NoSuchKey", "NotFound"):
            return None
        raise
    body = response["Body"].read()
    return json.loads(body.decode("utf-8"))


def maintenance_already_completed(
    bucket: str,
    key: str,
    region_name: str,
) -> bool:
    """Return True when a maintenance marker exists for the given key."""
    return read_maintenance_marker(bucket, key, region_name=region_name) is not None


def write_maintenance_marker(
    bucket: str,
    key: str,
    payload: Dict[str, Any],
    region_name: str,
) -> None:
    """Write ``payload`` as JSON to ``s3://bucket/key``."""
    s3_client = boto3.client("s3", region_name=region_name)
    s3_client.put_object(
        Bucket=normalize_s3_bucket(bucket),
        Key=key,
        Body=json.dumps(payload).encode("utf-8"),
        ContentType="application/json",
    )


def build_maintenance_payload(
    full_table_name: str,
    maintenance_date: str,
    environment: str,
    dag_name: str,
    run_vacuum: bool,
    run_optimize: bool,
) -> Dict[str, Any]:
    """Build the JSON body stored after successful maintenance."""
    return {
        "full_table_name": full_table_name,
        "maintenance_date": maintenance_date,
        "environment": environment,
        "dag_name": dag_name,
        "run_vacuum": run_vacuum,
        "run_optimize": run_optimize,
        "ts_completed": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def resolve_marker_location(
    state_bucket: str,
    environment: str,
    full_table_name: str,
    maintenance_date: str,
    state_prefix: str,
) -> Tuple[str, str]:
    """Return ``(bucket_name, key)`` for a table's daily maintenance marker."""
    bucket_name = normalize_s3_bucket(state_bucket)
    key = build_marker_key(
        environment=environment,
        full_table_name=full_table_name,
        maintenance_date=maintenance_date,
        state_prefix=state_prefix,
    )
    return bucket_name, key
