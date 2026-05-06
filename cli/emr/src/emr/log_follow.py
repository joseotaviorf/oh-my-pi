"""Poll EMR step logs from S3 and print new bytes (stdout/stderr gzip or plain)."""

from __future__ import annotations

import gzip
import sys
from typing import Any

from botocore.exceptions import ClientError


def parse_s3_uri(uri: str) -> tuple[str, str]:
    """Return ``(bucket, key_prefix)`` without leading/trailing slashes on the key."""
    if not uri.startswith("s3://"):
        raise ValueError(f"Not an s3 URI: {uri!r}")
    rest = uri[5:]
    bucket, _, key = rest.partition("/")
    if not bucket:
        raise ValueError(f"Invalid s3 URI: {uri!r}")
    return bucket, key.strip().rstrip("/")


def step_logs_prefix(log_uri: str, cluster_id: str, step_id: str) -> tuple[str, str]:
    """Bucket and key prefix ending with ``/`` for one EMR step's log objects."""
    bucket, base = parse_s3_uri(log_uri)
    base = base.strip("/")
    prefix = f"{base}/{cluster_id}/steps/{step_id}/"
    return bucket, prefix


_CONTROLLER_KEYS = ("controller.gz", "controller")
_STDOUT_KEYS = ("stdout.gz", "stdout")
_STDERR_KEYS = ("stderr.gz", "stderr")


def _decode_log_body(body: bytes, *, name: str) -> str:
    if not body:
        return ""
    if name.endswith(".gz"):
        try:
            return gzip.decompress(body).decode("utf-8", errors="replace")
        except OSError:
            return body.decode("utf-8", errors="replace")
    return body.decode("utf-8", errors="replace")


class StepLogTailer:
    """Prints appended content from EMR step ``stdout`` / ``stderr`` objects on S3."""

    def __init__(self) -> None:
        self._last_len: dict[str, int] = {}

    def poll(self, s3_client: Any, bucket: str, key_prefix: str) -> None:
        self._poll_one_stream(
            s3_client, bucket, key_prefix, "controller", _CONTROLLER_KEYS
        )
        self._poll_one_stream(s3_client, bucket, key_prefix, "stdout", _STDOUT_KEYS)
        self._poll_one_stream(s3_client, bucket, key_prefix, "stderr", _STDERR_KEYS)

    def _poll_one_stream(
        self,
        s3_client: Any,
        bucket: str,
        key_prefix: str,
        stream_id: str,
        candidates: tuple[str, ...],
    ) -> None:
        for rel in candidates:
            key = key_prefix + rel
            try:
                resp = s3_client.get_object(Bucket=bucket, Key=key)
            except ClientError as e:
                code = e.response.get("Error", {}).get("Code", "")
                if code in ("404", "NoSuchKey", "NotFound"):
                    continue
                raise
            body = resp["Body"].read()
            text = _decode_log_body(body, name=rel)
            prev = self._last_len.get(stream_id, 0)
            if len(text) < prev:
                prev = 0
            if len(text) > prev:
                sys.stdout.write(text[prev:])
                sys.stdout.flush()
                self._last_len[stream_id] = len(text)
            return
