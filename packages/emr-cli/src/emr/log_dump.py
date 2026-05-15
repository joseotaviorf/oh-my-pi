"""Download EMR-related log objects from S3 under ``dump_logs_base_uri`` + relative path."""

from __future__ import annotations

import sys
from pathlib import PurePosixPath
from typing import Any, TextIO

from botocore.exceptions import ClientError

from emr.log_follow import decode_log_body, parse_s3_uri


def sanitize_log_relative_path(raw: str) -> str:
    """Normalize user path: no ``..``, no absolute POSIX paths, non-empty."""
    s = raw.strip()
    if not s:
        raise ValueError("relative path must be non-empty")
    if s.startswith("/"):
        raise ValueError("relative path must not start with '/'")
    parts = PurePosixPath(s).parts
    if ".." in parts:
        raise ValueError("relative path must not contain '..'")
    return PurePosixPath(*parts).as_posix()


def bucket_and_key_prefix(dump_logs_base_uri: str, relative: str) -> tuple[str, str]:
    """Return ``(bucket, key_prefix)`` for listing / fetching under ``dump_logs_base_uri``."""
    bucket, base_key = parse_s3_uri(dump_logs_base_uri)
    base_key = base_key.strip("/")
    rel = sanitize_log_relative_path(relative)
    if base_key:
        prefix = f"{base_key}/{rel}"
    else:
        prefix = rel
    return bucket, prefix


def _list_all_keys(s3_client: Any, bucket: str, prefix: str) -> list[str]:
    keys: list[str] = []
    paginator = s3_client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents") or []:
            k = obj.get("Key")
            if k:
                keys.append(str(k))
    keys.sort()
    return keys


def dump_logs(
    s3_client: Any,
    *,
    dump_logs_base_uri: str,
    relative_path: str,
    stream: TextIO | None = None,
) -> None:
    """Print all S3 objects whose keys start with ``dump_logs_base_uri`` + ``relative_path``.

    Objects are printed in key order. Each object is prefixed with a banner line.
    Gzip-compressed bodies are decompressed like step log tailing.
    """
    out = stream if stream is not None else sys.stdout
    bucket, prefix = bucket_and_key_prefix(dump_logs_base_uri, relative_path)
    keys = _list_all_keys(s3_client, bucket, prefix)
    if not keys:
        raise ValueError(
            f"No S3 objects found under s3://{bucket}/{prefix} "
            "(check dump_logs_base_uri in config and the relative path)"
        )
    for key in keys:
        if key.endswith("/"):
            continue
        try:
            resp = s3_client.get_object(Bucket=bucket, Key=key)
        except ClientError as e:
            code = e.response.get("Error", {}).get("Code", "")
            if code in ("404", "NoSuchKey", "NotFound"):
                continue
            raise
        body: bytes = resp["Body"].read()
        name = key.rsplit("/", 1)[-1]
        text = decode_log_body(body, name=name)
        out.write(f"=== s3://{bucket}/{key} ===\n")
        out.write(text)
        if text and not text.endswith("\n"):
            out.write("\n")
