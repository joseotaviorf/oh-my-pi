"""Poll JSON result objects written by PySpark validation jobs on S3."""

from __future__ import annotations

import json
import time
from typing import Any

import boto3
from botocore.exceptions import ClientError

RESULT_JSON_PREFIX = "RESULT_JSON="

DEFAULT_RESULT_FETCH_RETRIES = 12
DEFAULT_RESULT_FETCH_DELAY_SEC = 5.0

_NOT_FOUND_CODES = frozenset({"NoSuchKey", "404", "NotFound"})


def split_s3_uri(uri: str) -> tuple[str, str]:
    normalized = uri.strip()
    for scheme in ("s3://", "s3n://", "s3a://"):
        if normalized.startswith(scheme):
            normalized = normalized[len(scheme) :]
            break
    else:
        raise ValueError(f"expected s3:// URI, got {uri!r}")
    bucket, _, key = normalized.partition("/")
    if not bucket or not key:
        raise ValueError(f"invalid s3:// URI: {uri!r}")
    return bucket, key


def fetch_json_from_s3(
    result_s3_uri: str,
    *,
    retries: int = DEFAULT_RESULT_FETCH_RETRIES,
    delay_sec: float = DEFAULT_RESULT_FETCH_DELAY_SEC,
    region: str | None = None,
) -> dict[str, Any] | None:
    """Poll until the JSON object exists or retries are exhausted."""
    bucket, key = split_s3_uri(result_s3_uri)
    client_kwargs: dict[str, Any] = {}
    if region:
        client_kwargs["region_name"] = region
    client = boto3.client("s3", **client_kwargs)

    for attempt in range(retries):
        try:
            response = client.get_object(Bucket=bucket, Key=key)
            payload = json.loads(response["Body"].read().decode("utf-8"))
            if isinstance(payload, dict):
                return payload
            return None
        except ClientError as exc:
            code = exc.response.get("Error", {}).get("Code", "")
            if code not in _NOT_FOUND_CODES:
                raise
            if attempt < retries - 1:
                time.sleep(delay_sec)
    return None


def format_result_json_line(payload: dict[str, Any]) -> str:
    return RESULT_JSON_PREFIX + json.dumps(payload, default=str)


def parse_result_json_line(text: str) -> dict[str, Any] | None:
    for line in text.splitlines():
        if line.startswith(RESULT_JSON_PREFIX):
            payload = json.loads(line[len(RESULT_JSON_PREFIX) :])
            if isinstance(payload, dict):
                return payload
    marker_idx = text.find(RESULT_JSON_PREFIX)
    if marker_idx >= 0:
        decoder = json.JSONDecoder()
        payload, _ = decoder.raw_decode(text, marker_idx + len(RESULT_JSON_PREFIX))
        if isinstance(payload, dict):
            return payload
    return None
