"""Background S3 poller — compare as artifacts land, incremental reports."""

from __future__ import annotations

import json
import logging
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from baseline import baseline_from_s3_payload, format_table_label, save_baseline_files
from cluster_bootstrap import load_session, save_session, update_session_after_compare
from compare import compare_results
from emr_runner import SqlStager, download_json_from_s3, emr_step_execution_start_ts, emr_step_failure_reason, emr_step_state, object_exists
from manifest import (
    TERMINAL_STATUSES,
    RunManifest,
    ValidationJob,
    artifact_ready,
    dedupe_manifest_jobs,
    load_manifest,
    save_manifest,
    update_job,
)
from manual_check import MANUAL_CHECK_STATUS, is_manual_check_error, manual_check_message
from models import EmrTableResult, TableBaseline, ValidationResult
from profile import profile_from_dict

from report import finalize_dag_reports, print_live_summary, write_partial_report

logger = logging.getLogger(__name__)

SKILL_DIR = Path(__file__).resolve().parent
RESULTS_FILE = SKILL_DIR / "validation_results.json"
WATCHERS_DIR = SKILL_DIR / "watchers"


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


@dataclass
class WatchConfig:
    run_id: str
    emr_env: str = "prod"
    poll_interval_sec: int = 15
    job_timeout_sec: int = 3600
    manual_check_timeout_sec: int = 300
    global_timeout_sec: Optional[int] = None
    skip_sample: bool = True
    skip_profile: bool = False
    domain_filter: Optional[str] = None
    dag_filter: Optional[str] = None


def _mark_job_manual_check(job: ValidationJob, reason: str) -> None:
    job.status = "manual_check"
    job.verdict = MANUAL_CHECK_STATUS
    job.error = manual_check_message(reason)
    job.completed_at = _utc_now_iso()


def _is_emr_step_failure_reason(reason: str) -> bool:
    """Return True if reason indicates a terminal EMR step failure (not timeout)."""
    lower = reason.lower()
    return any(
        state in lower
        for state in ("emr step failed", "emr step cancelled", "emr step interrupted")
    )


def _mark_job_emr_failure(
    job: ValidationJob,
    reason: str,
    *,
    cluster_id: Optional[str] = None,
    emr_env: str = "prod",
) -> None:
    """Mark job as error (FAIL status) for hard EMR step failures."""
    detailed_reason = reason
    if cluster_id and job.emr_step_id:
        step_failure_msg = emr_step_failure_reason(
            cluster_id, job.emr_step_id, emr_env=emr_env
        )
        if step_failure_msg:
            detailed_reason = step_failure_msg
    job.status = "error"
    job.verdict = "FAIL"
    job.error = detailed_reason
    job.completed_at = _utc_now_iso()


def _watch_elapsed_start(
    job: ValidationJob,
    watch_started_at: float,
    *,
    cluster_id: Optional[str] = None,
    emr_env: str = "prod",
) -> Optional[float]:
    """Return epoch seconds when EMR watch timeout should start, or None if not yet running."""
    if job.status not in {"running", "emr_done", "baseline_done"}:
        return None

    if cluster_id and job.emr_step_id:
        state = emr_step_state(cluster_id, job.emr_step_id, emr_env=emr_env)
        if state == "PENDING":
            return None
        if state == "RUNNING":
            exec_start = emr_step_execution_start_ts(
                cluster_id,
                job.emr_step_id,
                emr_env=emr_env,
            )
            if exec_start is not None:
                return max(exec_start, watch_started_at)
            return watch_started_at
        if state in {"COMPLETED", "FAILED", "CANCELLED", "INTERRUPTED"}:
            return watch_started_at

    ts = job.emr_submitted_at or job.baseline_done_at
    if not ts:
        return None
    try:
        emr_start = datetime.fromisoformat(ts).timestamp()
    except ValueError:
        return None
    return max(emr_start, watch_started_at)


def _manual_check_reason(
    job: ValidationJob,
    config: WatchConfig,
    watch_started_at: float,
    *,
    cluster_id: Optional[str] = None,
) -> Optional[str]:
    if job.status in TERMINAL_STATUSES:
        return None

    if cluster_id and job.emr_step_id:
        state = emr_step_state(cluster_id, job.emr_step_id, emr_env=config.emr_env)
        if state == "PENDING":
            return None
        if state in {"FAILED", "CANCELLED", "INTERRUPTED"}:
            return f"EMR step {state.lower()}"

    start = _watch_elapsed_start(
        job,
        watch_started_at,
        cluster_id=cluster_id,
        emr_env=config.emr_env,
    )
    if start is None:
        return None
    elapsed = time.time() - start
    if elapsed > config.job_timeout_sec:
        return f"exceeded hard job timeout ({config.job_timeout_sec}s)"
    if elapsed > config.manual_check_timeout_sec:
        return (
            f"exceeded manual check threshold ({config.manual_check_timeout_sec}s) — "
            "validate this table separately with a longer timeout"
        )
    return None


def _parse_submitted_ts(job: ValidationJob) -> float:
    if not job.submitted_at:
        return time.time()
    try:
        return datetime.fromisoformat(job.submitted_at).timestamp()
    except ValueError:
        return time.time()


def _job_timed_out(job: ValidationJob, job_timeout_sec: int) -> bool:
    """Legacy helper — prefer _manual_check_reason for watch loop."""
    if job.status in TERMINAL_STATUSES:
        return False
    if not job.submitted_at:
        return False
    return (time.time() - _parse_submitted_ts(job)) > job_timeout_sec


def _load_baseline_from_s3(uri: str, *, emr_env: str) -> Optional[TableBaseline]:
    data = download_json_from_s3(uri, emr_env=emr_env)
    if not data:
        return None
    return baseline_from_s3_payload(data)


def _load_emr_from_s3(
    stager: SqlStager,
    job: ValidationJob,
    *,
    emr_env: str,
) -> Optional[dict]:
    uris = [
        job.emr_s3_uri,
        stager.legacy_emr_result_uri_for(job.domain, job.dag, job.layer, job.table),
    ]
    for uri in uris:
        if uri and object_exists(uri, emr_env=emr_env):
            payload = download_json_from_s3(uri, emr_env=emr_env)
            if payload is not None:
                return payload
    return None


def _emr_from_payload(payload: dict) -> EmrTableResult:
    schema = [tuple(item) for item in payload.get("schema", [])]
    return EmrTableResult(
        schema=schema,
        count=int(payload.get("count", 0)),
        sample=payload.get("sample", []),
        profile=profile_from_dict(payload.get("profile")),
        error=payload.get("error"),
    )


def _refresh_job_artifacts(
    job: ValidationJob,
    stager: SqlStager,
    *,
    emr_env: str,
) -> ValidationJob:
    if job.status in TERMINAL_STATUSES:
        return job

    if job.baseline_s3_uri and artifact_ready(job.baseline_s3_uri, emr_env=emr_env):
        if not job.baseline_done_at:
            job.baseline_done_at = _utc_now_iso()

    if _load_emr_from_s3(stager, job, emr_env=emr_env) is not None:
        if not job.emr_done_at:
            job.emr_done_at = _utc_now_iso()

    if job.baseline_done_at and job.emr_done_at:
        if job.status not in {"compared", "error", "timeout", "manual_check"}:
            job.status = "emr_done"
    elif job.baseline_done_at:
        if job.status == "submitted":
            job.status = "baseline_done"

    return job


def _try_compare_job(
    job: ValidationJob,
    stager: SqlStager,
    *,
    emr_env: str,
    skip_sample: bool,
    skip_profile: bool,
) -> Optional[ValidationResult]:
    refreshed = _refresh_job_artifacts(job, stager, emr_env=emr_env)
    if not (refreshed.baseline_done_at and refreshed.emr_done_at):
        return None
    return _compare_job(
        refreshed,
        stager,
        emr_env=emr_env,
        skip_sample=skip_sample,
        skip_profile=skip_profile,
    )


def _compare_job(
    job: ValidationJob,
    stager: SqlStager,
    *,
    emr_env: str,
    skip_sample: bool,
    skip_profile: bool,
) -> ValidationResult:
    label = format_table_label(job.layer, job.table)
    baseline = _load_baseline_from_s3(job.baseline_s3_uri, emr_env=emr_env)
    emr_payload = _load_emr_from_s3(stager, job, emr_env=emr_env)

    if baseline is None or baseline.error:
        message = baseline.error if baseline else "Missing baseline on S3"
        return ValidationResult(
            table=label,
            baseline_count=baseline.count if baseline else 0,
            emr_count=0,
            count_delta_pct=0.0,
            schema_match=False,
            schema_issues=[message],
            sample_match=False,
            status="FAIL",
            message=message,
        )

    if emr_payload is None:
        return ValidationResult(
            table=label,
            baseline_count=baseline.count,
            emr_count=0,
            count_delta_pct=100.0,
            schema_match=False,
            schema_issues=["Missing EMR result on S3"],
            sample_match=False,
            status="FAIL",
            message="Missing EMR result on S3",
        )

    save_baseline_files(baseline, job.domain, s3_uri=job.baseline_s3_uri, emr_env=emr_env)
    return compare_results(
        baseline,
        _emr_from_payload(emr_payload),
        skip_sample=skip_sample,
        skip_profile=skip_profile,
    )


def _result_from_terminal_job(
    job: ValidationJob,
    stager: Optional[SqlStager] = None,
    *,
    emr_env: str = "prod",
    skip_sample: bool = True,
    skip_profile: bool = False,
) -> ValidationResult:
    label = format_table_label(job.layer, job.table)
    if stager is not None and job.status not in {"compared", "error"}:
        refreshed = _refresh_job_artifacts(job, stager, emr_env=emr_env)
        if refreshed.baseline_done_at and refreshed.emr_done_at:
            return _compare_job(
                refreshed,
                stager,
                emr_env=emr_env,
                skip_sample=skip_sample,
                skip_profile=skip_profile,
            )
    if job.status in {"timeout", "manual_check"} or is_manual_check_error(job.error):
        message = job.error or manual_check_message("job timed out waiting for results")
        return ValidationResult(
            table=label,
            baseline_count=0,
            emr_count=0,
            count_delta_pct=0.0,
            schema_match=False,
            schema_issues=[message],
            sample_match=False,
            status=MANUAL_CHECK_STATUS,
            message=message,
        )
    if job.status == "error":
        message = job.error or "Submit or runtime error"
        return ValidationResult(
            table=label,
            baseline_count=0,
            emr_count=0,
            count_delta_pct=0.0,
            schema_match=False,
            schema_issues=[message],
            sample_match=False,
            status="FAIL",
            message=message,
        )
    verdict = job.verdict or "FAIL"
    return ValidationResult(
        table=label,
        baseline_count=0,
        emr_count=0,
        count_delta_pct=0.0,
        schema_match=verdict != "FAIL",
        schema_issues=[job.error] if job.error else [],
        sample_match=verdict != "FAIL",
        status=verdict,
        message=job.error or verdict,
    )


def _job_in_scope(job: ValidationJob, config: WatchConfig) -> bool:
    if config.domain_filter and job.domain != config.domain_filter:
        return False
    if config.dag_filter and job.dag != config.dag_filter:
        return False
    return True


def _update_dag_partial_reports(
    manifest: RunManifest,
    stager: SqlStager,
    config: WatchConfig,
) -> None:
    dag_keys = {(job.domain, job.dag) for job in manifest.jobs if _job_in_scope(job, config)}
    for domain, dag in sorted(dag_keys):
        results: List[ValidationResult] = []
        pending: List[ValidationJob] = []
        for job in manifest.jobs_for_dag(domain, dag):
            if job.status == "compared":
                results.append(
                    _compare_job(
                        job,
                        stager,
                        emr_env=config.emr_env,
                        skip_sample=config.skip_sample,
                        skip_profile=config.skip_profile,
                    )
                )
            elif job.status in {"error", "timeout", "manual_check"}:
                results.append(
                    _result_from_terminal_job(
                        job,
                        stager,
                        emr_env=config.emr_env,
                        skip_sample=config.skip_sample,
                        skip_profile=config.skip_profile,
                    )
                )
            else:
                pending.append(job)
        skipped = manifest.skipped_tables.get(f"{domain}/{dag}", [])
        write_partial_report(
            domain,
            dag,
            results,
            pending_jobs=pending,
            run_id=manifest.run_id,
            load_start_date=manifest.load_start_date,
            load_end_date=manifest.load_end_date,
            databricks_cluster_id=manifest.databricks_cluster_id,
            emr_cluster_id=manifest.emr_cluster_id,
            skipped_tables=skipped,
            stager=stager,
            emr_env=config.emr_env,
        )


def run_watch(config: WatchConfig) -> Tuple[RunManifest, Dict[str, List[ValidationResult]]]:
    """Poll S3 until all jobs terminal; write incremental reports per DAG."""
    manifest = load_manifest(config.run_id, emr_env=config.emr_env)
    before = len(manifest.jobs)
    manifest.jobs = dedupe_manifest_jobs(manifest.jobs)
    if len(manifest.jobs) != before:
        logger.warning(
            "Deduped manifest before watch: %s -> %s jobs",
            before,
            len(manifest.jobs),
        )
        save_manifest(manifest, emr_env=config.emr_env)
    stager = SqlStager(run_id=manifest.run_id, emr_env=config.emr_env)
    start_time = time.time()
    dag_results: Dict[str, List[ValidationResult]] = {}

    logger.info(
        "Watching run_id=%s (%s unique jobs, poll=%ss, manual_check=%ss, job_timeout=%ss)",
        manifest.run_id,
        len(manifest.jobs),
        config.poll_interval_sec,
        config.manual_check_timeout_sec,
        config.job_timeout_sec,
    )

    while True:
        if config.global_timeout_sec and (time.time() - start_time) > config.global_timeout_sec:
            logger.warning("Global timeout reached for run_id=%s", manifest.run_id)
            break

        changed = False
        for job in manifest.jobs:
            if not _job_in_scope(job, config):
                continue
            if job.status in TERMINAL_STATUSES:
                continue

            prev_baseline_done = bool(job.baseline_done_at)
            prev_emr_done = bool(job.emr_done_at)
            job = _refresh_job_artifacts(job, stager, emr_env=config.emr_env)

            if (
                job.baseline_done_at
                and job.emr_done_at
                and job.status not in {"compared", "error", "timeout"}
            ):
                result = _compare_job(
                    job,
                    stager,
                    emr_env=config.emr_env,
                    skip_sample=config.skip_sample,
                    skip_profile=config.skip_profile,
                )
                job.status = "compared"
                job.verdict = result.status
                job.error = result.message if result.status == "FAIL" else None
                job.completed_at = _utc_now_iso()
                update_job(manifest, job, emr_env=config.emr_env)
                changed = True
                logger.info("Compared %s → %s", job.table_label, result.status)
                continue

            manual_reason = _manual_check_reason(
                job,
                config,
                start_time,
                cluster_id=manifest.emr_cluster_id,
            )
            if manual_reason:
                late = _try_compare_job(
                    job,
                    stager,
                    emr_env=config.emr_env,
                    skip_sample=config.skip_sample,
                    skip_profile=config.skip_profile,
                )
                if late is not None:
                    job.status = "compared"
                    job.verdict = late.status
                    job.error = late.message if late.status == "FAIL" else None
                    job.completed_at = _utc_now_iso()
                    update_job(manifest, job, emr_env=config.emr_env)
                    changed = True
                    logger.info("Compared %s → %s (late artifact)", job.table_label, late.status)
                    continue
                if _is_emr_step_failure_reason(manual_reason):
                    _mark_job_emr_failure(
                        job,
                        manual_reason,
                        cluster_id=manifest.emr_cluster_id,
                        emr_env=config.emr_env,
                    )
                    update_job(manifest, job, emr_env=config.emr_env)
                    changed = True
                    logger.error("EMR step failure: %s (%s)", job.table_label, job.error)
                    continue
                _mark_job_manual_check(job, manual_reason)
                update_job(manifest, job, emr_env=config.emr_env)
                changed = True
                logger.warning("Manual check: %s (%s)", job.table_label, manual_reason)
                continue

            if (
                (job.baseline_done_at and not prev_baseline_done)
                or (job.emr_done_at and not prev_emr_done)
            ):
                update_job(manifest, job, emr_env=config.emr_env)
                changed = True

        if changed:
            print_live_summary(manifest)
            _update_dag_partial_reports(manifest, stager, config)

        if manifest.is_complete():
            break
        if all(
            job.status in TERMINAL_STATUSES
            for job in manifest.jobs
            if _job_in_scope(job, config)
        ):
            break
        time.sleep(config.poll_interval_sec)

    for job in manifest.jobs:
        if not _job_in_scope(job, config):
            continue
        if job.status not in TERMINAL_STATUSES:
            _mark_job_manual_check(
                job,
                job.error or f"watch ended before completion (job_timeout={config.job_timeout_sec}s)",
            )
            update_job(manifest, job, emr_env=config.emr_env)

    dag_keys = {
        (job.domain, job.dag)
        for job in manifest.jobs
        if _job_in_scope(job, config)
    }
    for domain, dag in sorted(dag_keys):
        results: List[ValidationResult] = []
        for job in manifest.jobs_for_dag(domain, dag):
            if job.status == "compared":
                results.append(
                    _compare_job(
                        job,
                        stager,
                        emr_env=config.emr_env,
                        skip_sample=config.skip_sample,
                        skip_profile=config.skip_profile,
                    )
                )
            else:
                results.append(
                    _result_from_terminal_job(
                        job,
                        stager,
                        emr_env=config.emr_env,
                        skip_sample=config.skip_sample,
                        skip_profile=config.skip_profile,
                    )
                )

        dag_key = f"{domain}/{dag}"
        dag_results[dag_key] = results
        skipped = manifest.skipped_tables.get(dag_key, [])
        report_path = finalize_dag_reports(
            domain,
            dag,
            results,
            run_id=manifest.run_id,
            load_start_date=manifest.load_start_date,
            load_end_date=manifest.load_end_date,
            databricks_cluster_id=manifest.databricks_cluster_id,
            emr_cluster_id=manifest.emr_cluster_id,
            skipped_tables=skipped,
            stager=stager,
            emr_env=config.emr_env,
        )
        update_session_after_compare(
            domain=domain,
            dag_name=dag,
            report_path=report_path,
            results=results,
            load_start_date=manifest.load_start_date,
            load_end_date=manifest.load_end_date,
            databricks_cluster_id=manifest.databricks_cluster_id,
            emr_cluster_id=manifest.emr_cluster_id,
        )

    all_results = [item for sublist in dag_results.values() for item in sublist]
    RESULTS_FILE.write_text(
        json.dumps([asdict(result) for result in all_results], indent=2, default=str),
        encoding="utf-8",
    )
    save_manifest(manifest, emr_env=config.emr_env)
    print_live_summary(manifest, final=True)
    return manifest, dag_results


def spawn_detached_watch(
    run_id: str,
    *,
    domain: Optional[str] = None,
    dag: Optional[str] = None,
    emr_env: str = "prod",
    poll_interval_sec: int = 15,
    job_timeout_sec: int = 3600,
    manual_check_timeout_sec: int = 300,
    skip_profile: bool = False,
    skip_sample: bool = True,
) -> Tuple[int, Path]:
    """Spawn background watch subprocess; return pid and log path."""
    WATCHERS_DIR.mkdir(parents=True, exist_ok=True)
    log_path = WATCHERS_DIR / f"watch_{run_id}.log"
    pid_path = WATCHERS_DIR / f"{run_id}.pid"

    cmd = [
        sys.executable,
        str(SKILL_DIR / "validate.py"),
        "--phase",
        "watch",
        "--run-id",
        run_id,
        "--emr-env",
        emr_env,
        "--poll-interval",
        str(poll_interval_sec),
        "--job-timeout",
        str(job_timeout_sec),
        "--manual-check-timeout",
        str(manual_check_timeout_sec),
        "--no-detach",
    ]
    if domain:
        cmd.extend(["--domain", domain])
    if dag:
        cmd.extend(["--dag", dag])
    if skip_profile:
        cmd.append("--no-profile")
    if not skip_sample:
        cmd.append("--with-sample")

    with log_path.open("a", encoding="utf-8") as log_handle:
        process = subprocess.Popen(
            cmd,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            cwd=str(SKILL_DIR),
        )

    pid_path.write_text(str(process.pid), encoding="utf-8")
    session = load_session()
    session["watcher_pid"] = process.pid
    session["watcher_log"] = str(log_path)
    session["active_run_id"] = run_id
    save_session(session)
    return process.pid, log_path
