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
"""S3 console links for EMR runtime logs (nested LogUri layout)."""

from __future__ import annotations

from typing import Any, Optional
from urllib.parse import quote


def normalize_log_uri(log_uri: str) -> str:
    """Normalize EMR ``LogUri`` to ``s3://bucket/key`` for parsing."""
    normalized = log_uri.strip()
    if not normalized:
        return normalized
    if normalized.startswith("s3n://"):
        normalized = "s3://" + normalized[6:]
    elif not normalized.startswith("s3://"):
        normalized = f"s3://{normalized}"
    return normalized


def build_emr_logs_console_url_from_conf(
    conf: dict, *, step_id: Optional[str] = None
) -> str:
    """Build a nested LogUri console URL from provider ``emr_logs`` XCom payload."""
    job_flow_id = conf.get("job_flow_id")
    log_uri = conf.get("log_uri")
    region_name = conf.get("region_name")
    if not job_flow_id or not log_uri or not region_name:
        return ""
    return build_emr_logs_console_url(
        log_uri=log_uri,
        cluster_id=job_flow_id,
        region_name=region_name,
        step_id=step_id,
    )


def build_emr_logs_console_url(
    *,
    log_uri: str,
    cluster_id: str,
    region_name: str,
    step_id: Optional[str] = None,
    aws_domain: str = "console.aws.amazon.com",
) -> str:
    """
    Build an AWS S3 console URL for EMR cluster or step runtime logs.

    EMR writes logs under ``{LogUri}/{cluster_id}/`` with step logs in
    ``{LogUri}/{cluster_id}/steps/{step_id}/``. The built-in ``EmrLogsLink``
    only prefixes ``{cluster_id}/`` and breaks when ``LogUri`` contains a
    nested path such as ``s3://bucket/logs/jobs/{dag_id}``.
    """
    bucket, prefix = _parse_s3_location(normalize_log_uri(log_uri))
    full_prefix = f"{prefix.rstrip('/')}/{cluster_id}/"
    if step_id:
        full_prefix += f"steps/{step_id}/"
    encoded_prefix = quote(full_prefix, safe="")
    return (
        f"https://{aws_domain}/s3/buckets/{bucket}"
        f"?region={region_name}&prefix={encoded_prefix}"
    )


def get_cluster_log_uri(
    emr_client: Any, cluster_id: str, *, fallback_log_uri: Optional[str] = None
) -> Optional[str]:
    """Return the cluster ``LogUri`` from EMR or *fallback_log_uri*."""
    log_uri = fallback_log_uri
    if not log_uri:
        try:
            response = emr_client.describe_cluster(ClusterId=cluster_id)
            log_uri = response["Cluster"].get("LogUri")
        except Exception as exc:  # noqa: BLE001 - best-effort; token may expire on resume
            if _is_expired_token_error(exc):
                return None
            raise
    if not log_uri:
        return None
    return normalize_log_uri(log_uri)


def _is_expired_token_error(exc: BaseException) -> bool:
    code = getattr(exc, "response", None)
    if isinstance(code, dict):
        err = code.get("Error", {})
        if err.get("Code") in ("ExpiredToken", "ExpiredTokenException"):
            return True
    message = str(exc)
    return "ExpiredToken" in message


def build_step_log_s3_uri(
    log_uri: str, cluster_id: str, step_id: str, filename: str
) -> str:
    """Build ``s3://bucket/.../steps/{step_id}/{filename}`` from cluster LogUri."""
    bucket, prefix = _parse_s3_location(normalize_log_uri(log_uri))
    key = f"{prefix.rstrip('/')}/{cluster_id}/steps/{step_id}/{filename}"
    return f"s3://{bucket}/{key}"


def _parse_s3_location(s3_uri: str) -> tuple[str, str]:
    """Parse ``s3://bucket/key/prefix`` (or ``s3n://``) into bucket and key prefix."""
    normalized = normalize_log_uri(s3_uri)[5:]  # strip s3://
    normalized = normalized.rstrip("/")
    bucket, _, key = normalized.partition("/")
    if not bucket:
        raise ValueError(f"Invalid S3 URI: {s3_uri!r}")
    return bucket, key
