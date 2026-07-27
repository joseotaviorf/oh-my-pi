#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
"""Surface EMR step FailureDetails and driver stdout in Airflow task logs on failure."""

from __future__ import annotations

import gzip
import io
import logging
import re
import time
from typing import Any, Iterable, List, Optional, Tuple

from emr_plugin.s3_log_links import (
    _is_expired_token_error,
    build_step_log_s3_uri,
    get_cluster_log_uri,
    normalize_log_uri,
)

# Driver application logs live in stdout.gz.
# stderr.gz is YARN/hadoop noise — never use it.
STEP_STDOUT_FILENAME = "stdout.gz"

# EMR uploads stdout.gz after terminal state; on failures wait up to ~3 min.
S3_LOG_UPLOAD_RETRIES = 20
S3_LOG_UPLOAD_DELAY_SECONDS = 10.0

_PYTHON_DRIVER_LOG_RE = re.compile(r"^INFO:\w+:\d{4}-\d{2}-\d{2}")
_SPARK_LOG4J_INFRA_RE = re.compile(
    r"^\d{2}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2}\s+(INFO|DEBUG|TRACE)\s+"
)


def log_trigger_failure_event(logger: logging.Logger, event: Any) -> None:
    """Log FailureDetails embedded in a deferrable trigger event, if present."""
    if not event or not isinstance(event, dict):
        return
    logger.error("EMR step trigger failure event: %s", event)
    for failure_details in _extract_failure_details(event):
        logger.error("EMR step FailureDetails (trigger): %s", failure_details)


def log_emr_step_failures(
    *,
    emr_client: Any,
    s3_client: Any,
    cluster_id: str,
    step_ids: Iterable[str],
    logger: logging.Logger,
    log_uri: Optional[str] = None,
    max_log_lines: int = 200,
    max_log_bytes: int = 65536,
    s3_fetch_retries: int = S3_LOG_UPLOAD_RETRIES,
    s3_fetch_delay_seconds: float = S3_LOG_UPLOAD_DELAY_SECONDS,
) -> None:
    """
    For each failed step, log ``FailureDetails`` and tail ``stdout.gz``.

    Waits for S3 upload lag on failure only. Does not use stderr or ``LogFile``.
    """
    resolved_log_uri = log_uri or get_cluster_log_uri(emr_client, cluster_id)
    for step_id in step_ids:
        if not step_id:
            continue
        failure_details = None
        try:
            response = emr_client.describe_step(ClusterId=cluster_id, StepId=step_id)
            failure_details = response["Step"]["Status"].get("FailureDetails")
        except Exception as exc:  # noqa: BLE001
            if _is_expired_token_error(exc):
                logger.error(
                    "EMR step %s FailureDetails unavailable (AWS token expired); "
                    "refresh aws_default and use EMR Step Logs link",
                    step_id,
                )
            else:
                logger.error("EMR step %s could not describe step: %s", step_id, exc)
        if failure_details:
            logger.error("EMR step %s FailureDetails: %s", step_id, failure_details)

        if not resolved_log_uri:
            if not log_uri:
                logger.error(
                    "EMR step %s stdout unavailable (LogUri unknown); "
                    "use EMR Step Logs link",
                    step_id,
                )
            continue

        uri, tail = tail_step_stdout_log(
            s3_client,
            resolved_log_uri,
            cluster_id,
            step_id,
            max_lines=max_log_lines,
            max_bytes=max_log_bytes,
            retries=s3_fetch_retries,
            retry_delay_seconds=s3_fetch_delay_seconds,
        )
        if tail and uri:
            logger.error("EMR step %s runtime log tail (%s):\n%s", step_id, uri, tail)
        else:
            logger.error(
                "EMR step %s stdout not yet available in S3; use EMR Step Logs link",
                step_id,
            )


def tail_step_stdout_log(
    s3_client: Any,
    log_uri: str,
    cluster_id: str,
    step_id: str,
    *,
    max_lines: int = 200,
    max_bytes: int = 65536,
    retries: int = S3_LOG_UPLOAD_RETRIES,
    retry_delay_seconds: float = S3_LOG_UPLOAD_DELAY_SECONDS,
) -> Tuple[Optional[str], Optional[str]]:
    """Return ``(s3_uri, tail)`` from step ``stdout.gz`` only."""
    uri = build_step_log_s3_uri(log_uri, cluster_id, step_id, STEP_STDOUT_FILENAME)
    tail = fetch_s3_object_tail(
        s3_client,
        uri,
        max_lines=max_lines,
        max_bytes=max_bytes,
        retries=retries,
        retry_delay_seconds=retry_delay_seconds,
        wait_for_application_content=True,
    )
    if tail and tail.strip() and not tail.startswith("(could not fetch log"):
        return uri, tail
    return None, None


def fetch_s3_object_tail(
    s3_client: Any,
    s3_uri: str,
    *,
    max_lines: int = 200,
    max_bytes: int = 65536,
    retries: int = 3,
    retry_delay_seconds: float = 5.0,
    wait_for_application_content: bool = False,
) -> Optional[str]:
    """Download the tail of an S3 object (supports ``.gz``)."""
    bucket, key = _parse_s3_uri(s3_uri)
    last_error: Optional[Exception] = None
    last_text: Optional[str] = None
    for attempt in range(retries):
        try:
            response = s3_client.get_object(Bucket=bucket, Key=key)
            body = response["Body"].read()
            text = _decode_log_body(body, key)
            last_text = text
            if wait_for_application_content and not _stdout_has_application_content(
                text
            ):
                if attempt + 1 < retries:
                    time.sleep(retry_delay_seconds)
                    continue
            return _tail_text(text, max_lines=max_lines, max_bytes=max_bytes)
        except Exception as exc:  # noqa: BLE001 - log fetch is best-effort
            last_error = exc
            if _is_expired_token_error(exc):
                return (
                    f"(could not fetch log from {s3_uri}: AWS session token expired; "
                    "refresh aws_default connection)"
                )
            if attempt + 1 < retries:
                time.sleep(retry_delay_seconds)
    if last_text is not None:
        return _tail_text(last_text, max_lines=max_lines, max_bytes=max_bytes)
    if last_error is not None:
        return f"(could not fetch log from {s3_uri}: {last_error})"
    return None


def _stdout_has_application_content(text: str) -> bool:
    """True when stdout contains Python driver logs (not just Spark JVM bootstrap)."""
    if "Traceback (most recent call last)" in text:
        return True
    for line in text.splitlines():
        stripped = line.strip()
        if _PYTHON_DRIVER_LOG_RE.match(stripped):
            return True
        if re.match(r"^(WARNING|ERROR|CRITICAL):\w+:\d{4}-\d{2}-\d{2}", stripped):
            return True
    return False


def _extract_failure_details(obj: Any) -> List[Any]:
    found: List[Any] = []
    _walk_failure_details(obj, found)
    return found


def _walk_failure_details(obj: Any, found: List[Any]) -> None:
    if isinstance(obj, dict):
        failure_details = obj.get("FailureDetails")
        if failure_details:
            found.append(failure_details)
        for value in obj.values():
            _walk_failure_details(value, found)
    elif isinstance(obj, list):
        for item in obj:
            _walk_failure_details(item, found)


def _decode_log_body(body: bytes, key: str) -> str:
    if key.endswith(".gz"):
        with gzip.GzipFile(fileobj=io.BytesIO(body)) as gz_file:
            raw = gz_file.read()
    else:
        raw = body
    return raw.decode("utf-8", errors="replace")


def _tail_text(
    text: str, *, max_lines: int, max_bytes: int, application_only: bool = True
) -> str:
    lines: List[str] = text.splitlines()
    if len(lines) > max_lines:
        lines = lines[-max_lines:]
    if application_only:
        filtered = _drop_spark_jvm_infra_lines(lines)
        if filtered:
            lines = filtered
    tail = "\n".join(lines)
    encoded = tail.encode("utf-8")
    if len(encoded) > max_bytes:
        tail = encoded[-max_bytes:].decode("utf-8", errors="replace")
    return tail


def _drop_spark_jvm_infra_lines(lines: Iterable[str]) -> List[str]:
    """Drop SparkContext JVM INFO lines; keep Python driver logs."""
    kept: List[str] = []
    in_traceback = False
    for line in lines:
        stripped = line.strip()
        if "Traceback (most recent call last)" in line:
            in_traceback = True
            kept.append(line)
            continue
        if in_traceback:
            kept.append(line)
            if (
                stripped
                and not stripped.startswith("File ")
                and "Error" not in stripped
            ):
                if not stripped[0].isspace() and "Traceback" not in line:
                    in_traceback = False
            continue
        if stripped and _SPARK_LOG4J_INFRA_RE.match(stripped):
            continue
        kept.append(line)
    return kept


def _parse_s3_uri(s3_uri: str) -> tuple[str, str]:
    from emr_plugin.s3_log_links import _parse_s3_location

    bucket, key = _parse_s3_location(normalize_log_uri(s3_uri))
    if not key:
        raise ValueError(f"Invalid S3 URI: {s3_uri!r}")
    return bucket, key
