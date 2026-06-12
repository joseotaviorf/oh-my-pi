"""S3-backed run manifest for async parallel validation."""

from __future__ import annotations

import json
import logging
import threading
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from emr_runner import (
    SqlStager,
    download_json_from_s3,
    object_exists,
    upload_json_to_s3,
)

logger = logging.getLogger(__name__)

_manifest_lock = threading.Lock()

TERMINAL_STATUSES = frozenset({"compared", "error", "timeout", "manual_check"})
ACTIVE_STATUSES = frozenset({"pending", "submitted", "running", "baseline_done", "emr_done"})
STALE_INFLIGHT_STATUSES = frozenset({"running", "baseline_done", "submitted", "emr_done"})

# Lower rank = more advanced (preferred when deduping duplicate job keys).
_STATUS_RANK = {
    "compared": 0,
    "manual_check": 1,
    "running": 2,
    "emr_done": 3,
    "baseline_done": 4,
    "submitted": 5,
    "pending": 6,
    "error": 7,
    "timeout": 8,
}


def _status_rank(status: str) -> int:
    return _STATUS_RANK.get(status, 99)


def _prefer_job(current: ValidationJob, candidate: ValidationJob) -> ValidationJob:
    """Keep the job with the most advanced status; ties keep richer metadata."""
    if _status_rank(candidate.status) < _status_rank(current.status):
        return candidate
    if _status_rank(candidate.status) > _status_rank(current.status):
        return current
    if candidate.baseline_done_at and not current.baseline_done_at:
        return candidate
    if candidate.emr_done_at and not current.emr_done_at:
        return candidate
    if candidate.emr_step_id and not current.emr_step_id:
        return candidate
    if candidate.verdict and not current.verdict:
        return candidate
    return current


def dedupe_manifest_jobs(jobs: List[ValidationJob]) -> List[ValidationJob]:
    """Collapse duplicate rows sharing the same job.key (domain/dag/layer/table)."""
    best: Dict[str, ValidationJob] = {}
    order: List[str] = []
    for job in jobs:
        if job.key not in best:
            best[job.key] = job
            order.append(job.key)
        else:
            best[job.key] = _prefer_job(best[job.key], job)
    return [best[key] for key in order]


def reset_stale_jobs(manifest: RunManifest) -> int:
    """Reset in-flight jobs stuck between submit and compare back to pending."""
    reset = 0
    for job in manifest.jobs:
        if job.status in TERMINAL_STATUSES:
            continue
        if job.status not in STALE_INFLIGHT_STATUSES:
            continue
        job.status = "pending"
        job.emr_step_id = ""
        job.emr_submitted_at = ""
        job.emr_done_at = ""
        job.baseline_done_at = ""
        job.submitted_at = ""
        job.completed_at = ""
        job.error = None
        job.verdict = ""
        job.emr_s3_uri = ""
        reset += 1
    manifest.jobs = dedupe_manifest_jobs(manifest.jobs)
    return reset


def _utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


@dataclass
class ValidationJob:
    domain: str
    dag: str
    layer: str
    table: str
    status: str = "pending"
    baseline_s3_uri: str = ""
    emr_s3_uri: str = ""
    emr_step_id: str = ""
    error: Optional[str] = None
    verdict: str = ""
    submitted_at: str = ""
    completed_at: str = ""
    baseline_done_at: str = ""
    emr_submitted_at: str = ""
    emr_done_at: str = ""

    @property
    def key(self) -> str:
        return f"{self.domain}/{self.dag}/{self.layer}/{self.table}"

    @property
    def table_label(self) -> str:
        return f"{self.layer}/{self.table}"


@dataclass
class RunManifest:
    run_id: str
    load_start_date: str
    load_end_date: str
    baseline_git_ref: str = "master"
    created_at: str = ""
    databricks_cluster_id: str = ""
    emr_cluster_id: str = ""
    jobs: List[ValidationJob] = field(default_factory=list)
    skipped_tables: Dict[str, List[str]] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.created_at:
            self.created_at = _utc_now()

    @property
    def manifest_s3_uri(self) -> str:
        stager = SqlStager(run_id=self.run_id)
        return stager.manifest_uri()

    def job_by_key(self, domain: str, dag: str, layer: str, table: str) -> Optional[ValidationJob]:
        target = f"{domain}/{dag}/{layer}/{table}"
        for job in self.jobs:
            if job.key == target:
                return job
        return None

    def jobs_for_dag(self, domain: str, dag: str) -> List[ValidationJob]:
        return [job for job in self.jobs if job.domain == domain and job.dag == dag]

    def is_complete(self) -> bool:
        return all(job.status in TERMINAL_STATUSES for job in self.jobs)

    def counts(self) -> Dict[str, int]:
        totals = {
            "total": len(self.jobs),
            "pending": 0,
            "submitted": 0,
            "running": 0,
            "baseline_done": 0,
            "emr_done": 0,
            "compared": 0,
            "error": 0,
            "timeout": 0,
            "manual_check": 0,
        }
        for job in self.jobs:
            if job.status in totals:
                totals[job.status] += 1
            elif job.status in ACTIVE_STATUSES:
                totals["running"] += 1
        return totals


def manifest_from_dict(data: dict[str, Any]) -> RunManifest:
    jobs = [ValidationJob(**item) for item in data.get("jobs", [])]
    return RunManifest(
        run_id=data["run_id"],
        load_start_date=data["load_start_date"],
        load_end_date=data["load_end_date"],
        baseline_git_ref=data.get("baseline_git_ref", "master"),
        created_at=data.get("created_at", ""),
        databricks_cluster_id=data.get("databricks_cluster_id", ""),
        emr_cluster_id=data.get("emr_cluster_id", ""),
        jobs=jobs,
        skipped_tables=data.get("skipped_tables", {}),
    )


def manifest_to_dict(manifest: RunManifest) -> dict[str, Any]:
    return asdict(manifest)


def save_manifest(manifest: RunManifest, *, emr_env: str = "prod") -> str:
    manifest.jobs = dedupe_manifest_jobs(manifest.jobs)
    uri = manifest.manifest_s3_uri
    upload_json_to_s3(uri, manifest_to_dict(manifest), emr_env=emr_env)
    return uri


def load_manifest(run_id: str, *, emr_env: str = "prod") -> RunManifest:
    stager = SqlStager(run_id=run_id, emr_env=emr_env)
    uri = stager.manifest_uri()
    data = download_json_from_s3(uri, emr_env=emr_env)
    if data is None:
        raise FileNotFoundError(f"Manifest not found at {uri}")
    return manifest_from_dict(data)


def update_job(
    manifest: RunManifest,
    job: ValidationJob,
    *,
    emr_env: str = "prod",
    save: bool = True,
) -> None:
    with _manifest_lock:
        matched = any(existing.key == job.key for existing in manifest.jobs)
        for index, existing in enumerate(manifest.jobs):
            if existing.key == job.key:
                manifest.jobs[index] = job
        if not matched:
            manifest.jobs.append(job)
        if save:
            save_manifest(manifest, emr_env=emr_env)


def ensure_job_uris(
    manifest: RunManifest,
    job: ValidationJob,
    *,
    stager: Optional[SqlStager] = None,
) -> ValidationJob:
    stager = stager or SqlStager(run_id=manifest.run_id)
    if not job.baseline_s3_uri:
        job.baseline_s3_uri = stager.baseline_uri_for(
            job.domain, job.dag, job.layer, job.table
        )
    if not job.emr_s3_uri:
        job.emr_s3_uri = stager.emr_result_uri_for(
            job.domain, job.dag, job.layer, job.table
        )
    return job


def artifact_ready(uri: str, *, emr_env: str = "prod") -> bool:
    if not uri:
        return False
    return object_exists(uri, emr_env=emr_env)
