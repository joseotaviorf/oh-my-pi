"""Fetch EMR cluster stdout/stderr logs from S3."""

from __future__ import annotations

import gzip
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from aws import client_s3, logs_base_uri
from botocore.exceptions import ClientError

DAG_NAME_MARKERS = ("_scheduled", "_manual")
FAILED_STEP_STATES = frozenset({"FAILED"})
STEP_LOG_FILES = ("stdout.gz", "stderr.gz")
MAX_PARALLEL_LOG_WORKERS = 8


@dataclass
class FailedStepSummary:
    step_id: str
    name: str
    state: str
    started_at: datetime | None = None


@dataclass
class ClusterLogsResult:
    text: str
    dag_id: str | None
    steps_loaded: int
    steps_missing: int
    failed_steps: list[FailedStepSummary] = field(default_factory=list)
    message: str = ""


def parse_dag_id_from_cluster_name(cluster_name: str) -> str | None:
    """Extract DAG id from EMR cluster name (left of ``_scheduled`` / ``_manual``)."""
    for marker in DAG_NAME_MARKERS:
        if marker in cluster_name:
            return cluster_name.split(marker, 1)[0]
    return None


def _parse_s3_uri(uri: str) -> tuple[str, str]:
    if not uri.startswith("s3://"):
        raise ValueError(f"Not an s3 URI: {uri!r}")
    rest = uri[5:]
    bucket, _, key = rest.partition("/")
    if not bucket:
        raise ValueError(f"Invalid s3 URI: {uri!r}")
    return bucket, key.strip().rstrip("/")


def step_log_object_key(
    logs_base: str, dag_id: str, cluster_id: str, step_id: str, filename: str
) -> tuple[str, str]:
    bucket, base_key = _parse_s3_uri(logs_base)
    parts = [
        p
        for p in (base_key, dag_id, cluster_id, "steps", step_id, filename)
        if p
    ]
    return bucket, "/".join(parts)


def _decode_log_body(body: bytes) -> str:
    if not body:
        return ""
    try:
        return gzip.decompress(body).decode("utf-8", errors="replace")
    except OSError:
        return body.decode("utf-8", errors="replace")


def _format_step_ts(step: Any) -> str:
    if step.started_at is None:
        return "unknown time"
    ts = step.started_at.astimezone(timezone.utc)
    return ts.strftime("%Y-%m-%d %H:%M:%S UTC")


def _sort_steps(steps: list[Any]) -> list[Any]:
    min_dt = datetime.min.replace(tzinfo=timezone.utc)
    return sorted(steps, key=lambda step: step.started_at or min_dt)


def _failed_steps(steps: list[Any]) -> list[Any]:
    return [step for step in steps if step.state in FAILED_STEP_STATES]


def _to_failed_summary(step: Any) -> FailedStepSummary:
    return FailedStepSummary(
        step_id=step.step_id,
        name=step.name,
        state=step.state,
        started_at=step.started_at,
    )


def _fetch_log_object(s3: Any, bucket: str, key: str) -> str | None:
    try:
        resp = s3.get_object(Bucket=bucket, Key=key)
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        if code in ("404", "NoSuchKey", "NotFound"):
            return None
        raise
    body: bytes = resp["Body"].read()
    return _decode_log_body(body)


def _render_log_stream(
    s3: Any,
    logs_base: str,
    dag_id: str,
    cluster_id: str,
    step_id: str,
    filename: str,
    label: str,
) -> tuple[str, bool]:
    bucket, key = step_log_object_key(logs_base, dag_id, cluster_id, step_id, filename)
    s3_uri = f"s3://{bucket}/{key}"
    content = _fetch_log_object(s3, bucket, key)
    chunks = [f"--- {label}: {s3_uri} ---\n"]
    if content is None:
        chunks.append(f"({filename} not found)\n\n")
        return "".join(chunks), False
    chunks.append(content)
    if content and not content.endswith("\n"):
        chunks.append("\n")
    chunks.append("\n")
    return "".join(chunks), True


def _load_failed_step_logs(
    s3: Any,
    logs_base: str,
    dag_id: str,
    cluster_id: str,
    step: Any,
) -> tuple[str, bool]:
    if not step.step_id:
        return "", False

    header = (
        f"=== {step.name} ({step.step_id}) · {step.state} · "
        f"{_format_step_ts(step)} ===\n"
    )
    chunks = [header]
    step_loaded = False

    for filename in STEP_LOG_FILES:
        label = filename.removesuffix(".gz")
        stream_text, found = _render_log_stream(
            s3,
            logs_base,
            dag_id,
            cluster_id,
            step.step_id,
            filename,
            label,
        )
        chunks.append(stream_text)
        if found:
            step_loaded = True
    return "".join(chunks), step_loaded


def fetch_cluster_logs(
    info: Any,
    environment: str | None = None,
    region: str | None = None,
) -> ClusterLogsResult:
    dag_id = parse_dag_id_from_cluster_name(info.name)
    if not dag_id:
        return ClusterLogsResult(
            text="",
            dag_id=None,
            failed_steps=[],
            steps_loaded=0,
            steps_missing=0,
            message=(
                f"Could not parse DAG id from cluster name `{info.name}`. "
                f"Expected `_scheduled` or `_manual` in the name."
            ),
        )

    if not info.steps:
        return ClusterLogsResult(
            text="",
            dag_id=dag_id,
            failed_steps=[],
            steps_loaded=0,
            steps_missing=0,
            message="No EMR steps found for this cluster.",
        )

    failed = _sort_steps(_failed_steps(info.steps))
    failed_summaries = [_to_failed_summary(step) for step in failed]

    if not failed:
        return ClusterLogsResult(
            text="",
            dag_id=dag_id,
            failed_steps=[],
            steps_loaded=0,
            steps_missing=0,
            message="No failed steps on this cluster.",
        )

    base = logs_base_uri(environment)
    s3 = client_s3(region, environment)
    steps_with_ids = [step for step in failed if step.step_id]
    loaded = 0
    missing = 0
    step_chunks: list[str] = []

    if steps_with_ids:
        worker_count = min(MAX_PARALLEL_LOG_WORKERS, len(steps_with_ids))
        with ThreadPoolExecutor(max_workers=worker_count) as executor:
            results = list(
                executor.map(
                    lambda step: _load_failed_step_logs(
                        s3, base, dag_id, info.cluster_id, step
                    ),
                    steps_with_ids,
                )
            )
        for chunk_text, step_loaded in results:
            if chunk_text:
                step_chunks.append(chunk_text)
            if step_loaded:
                loaded += 1
            else:
                missing += 1

    if loaded == 0:
        return ClusterLogsResult(
            text="".join(step_chunks),
            dag_id=dag_id,
            failed_steps=failed_summaries,
            steps_loaded=0,
            steps_missing=missing,
            message=(
                f"No stdout.gz or stderr.gz found for {len(failed)} failed step(s) under "
                f"`{base}{dag_id}/{info.cluster_id}/steps/`."
            ),
        )

    return ClusterLogsResult(
        text="".join(step_chunks),
        dag_id=dag_id,
        failed_steps=failed_summaries,
        steps_loaded=loaded,
        steps_missing=missing,
        message=(
            f"Loaded stdout/stderr for {loaded} failed step(s)"
            + (f"; no logs for {missing} step(s)" if missing else "")
            + "."
        ),
    )
