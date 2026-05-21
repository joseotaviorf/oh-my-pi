"""Poll EMR step logs from S3 and print new bytes (stdout/stderr gzip or plain)."""

from __future__ import annotations

import gzip
import sys
import time
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


def list_object_keys(s3_client: Any, bucket: str, prefix: str) -> list[str]:
    """List object keys under ``prefix`` (same layout as ``dump-logs``)."""
    keys: list[str] = []
    paginator = s3_client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents") or []:
            k = obj.get("Key")
            if k and not str(k).endswith("/"):
                keys.append(str(k))
    return sorted(keys)


def decode_log_body(body: bytes, *, name: str) -> str:
    """Decode EMR log object bytes (gzip if ``name`` ends with ``.gz``)."""
    if not body:
        return ""
    if name.endswith(".gz"):
        try:
            return gzip.decompress(body).decode("utf-8", errors="replace")
        except OSError:
            return body.decode("utf-8", errors="replace")
    return body.decode("utf-8", errors="replace")


class StepLogTailer:
    """Print appended content from all log objects under an EMR step S3 prefix."""

    def __init__(self) -> None:
        self._last_len: dict[str, int] = {}
        self.saw_any_key = False
        self._empty_polls = 0

    def poll(self, s3_client: Any, bucket: str, key_prefix: str) -> bool:
        """Fetch new bytes from every object under ``key_prefix``. Returns True if any exist."""
        found = False
        for key in list_object_keys(s3_client, bucket, key_prefix):
            found = True
            self.saw_any_key = True
            self._poll_key(s3_client, bucket, key)
        return found

    def poll_with_stall_warning(
        self, s3_client: Any, bucket: str, key_prefix: str
    ) -> bool:
        """Poll step logs; warn on stderr after 3 consecutive empty S3 listings."""
        if self.poll(s3_client, bucket, key_prefix):
            self._empty_polls = 0
            return True
        self._empty_polls += 1
        if self._empty_polls == 3 and not self.saw_any_key:
            print(
                "No step log objects in S3 yet (EMR may upload only after the "
                "step finishes). Still polling…",
                file=sys.stderr,
                flush=True,
            )
        return False

    def _poll_key(self, s3_client: Any, bucket: str, key: str) -> None:
        try:
            resp = s3_client.get_object(Bucket=bucket, Key=key)
        except ClientError as e:
            code = e.response.get("Error", {}).get("Code", "")
            if code in ("404", "NoSuchKey", "NotFound"):
                return
            raise
        body = resp["Body"].read()
        name = key.rsplit("/", 1)[-1]
        text = decode_log_body(body, name=name)
        prev = self._last_len.get(key, 0)
        if len(text) < prev:
            prev = 0
        if len(text) > prev:
            if prev == 0 and text.strip():
                sys.stdout.write(f"=== s3://{bucket}/{key} ===\n")
            sys.stdout.write(text[prev:])
            sys.stdout.flush()
            self._last_len[key] = len(text)


def flush_step_logs_after_terminal(
    s3_client: Any,
    tailer: StepLogTailer,
    bucket: str,
    key_prefix: str,
    *,
    attempts: int = 6,
    delay_sec: float = 2.0,
) -> None:
    """EMR often uploads step logs only after the step ends; retry for S3 lag."""
    for i in range(attempts):
        tailer.poll(s3_client, bucket, key_prefix)
        if tailer.saw_any_key:
            return
        if i < attempts - 1:
            time.sleep(delay_sec)
