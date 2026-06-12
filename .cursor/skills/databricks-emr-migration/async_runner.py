"""Parallel fire-and-forget validation submit."""

from __future__ import annotations

import logging
import threading
import uuid
import yaml
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional, Set

from baseline import (
    DatabricksBaseline,
    TableScopeKey,
    _schema_from_describe,
    baseline_lookup_key,
    discover_tables,
    format_table_label,
    is_baseline_fresh,
    load_baseline_for_table,
    save_baseline_files,
    tables_needing_baseline,
)
from cluster_bootstrap import (
    is_emr_cluster_reusable,
    load_session,
    resolve_databricks_cluster,
    resolve_validation_emr_cluster,
    save_session,
)
from databricks_client import DatabricksAPI
from declaration import format_order_by_clause, get_z_order_by, resolve_order_by_cols
from emr_runner import (
    SqlStager,
    ensure_aws_credentials,
    parse_step_id_from_output,
    run_emr_cli,
    upload_text_to_s3,
    VALIDATE_JOB_REL,
)
from manifest import (
    RunManifest,
    ValidationJob,
    dedupe_manifest_jobs,
    ensure_job_uris,
    load_manifest,
    save_manifest,
    update_job,
)
from manual_check import is_manual_check_error, manual_check_message
from models import SchemaEntry, TableBaseline
from query_builders import build_describe_query
from sql_utils import load_pinned_sql

logger = logging.getLogger(__name__)

_db_context_lock = threading.Lock()
_baseline_key_locks: dict[str, threading.Lock] = {}
_baseline_key_locks_guard = threading.Lock()
_baseline_capture_cache: dict[str, tuple[Optional[object], Optional[str]]] = {}
_job_finalize_locks: dict[str, threading.Lock] = {}
_job_finalize_locks_guard = threading.Lock()


@dataclass
class SubmitConfig:
    domain: str
    dag: str
    load_start_date: str
    load_end_date: str
    baseline_git_ref: str = "master"
    databricks_profile: str = "PROD"
    databricks_cluster_id: str = ""
    emr_cluster_id: str = ""
    emr_env: str = "prod"
    staging_uri: Optional[str] = None
    skip_sample: bool = True
    skip_profile: bool = False
    timeout_sec: int = 300
    sample_limit: int = 100
    table_filter: Optional[str] = None
    table_allowlist: Optional[Set[TableScopeKey]] = None
    repo_root: Optional[Path] = None
    max_parallel: int = 5
    max_parallel_databricks: int = 3
    max_parallel_emr: int = 8
    allow_create_emr: bool = True
    new_emr_session: bool = False
    run_id: Optional[str] = None
    skipped_tables: Optional[List[str]] = None


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def build_manifest_for_dag(config: SubmitConfig) -> RunManifest:
    run_id = config.run_id or uuid.uuid4().hex
    tables = discover_tables(
        config.domain,
        config.dag,
        config.table_filter,
        repo_root=config.repo_root,
    )
    if config.table_allowlist is not None:
        tables = [
            (table_name, layer)
            for table_name, layer in tables
            if baseline_lookup_key(layer, table_name) in config.table_allowlist
        ]

    jobs: List[ValidationJob] = []
    stager = SqlStager(run_id=run_id, staging_uri=config.staging_uri, emr_env=config.emr_env)
    for table_name, layer in tables:
        job = ValidationJob(
            domain=config.domain,
            dag=config.dag,
            layer=layer,
            table=table_name,
            status="pending",
        )
        ensure_job_uris(RunManifest(run_id=run_id, load_start_date="", load_end_date=""), job, stager=stager)
        jobs.append(job)

    skipped_key = f"{config.domain}/{config.dag}"
    skipped_map = {}
    if config.skipped_tables:
        skipped_map[skipped_key] = list(config.skipped_tables)

    return RunManifest(
        run_id=run_id,
        load_start_date=config.load_start_date,
        load_end_date=config.load_end_date,
        baseline_git_ref=config.baseline_git_ref,
        databricks_cluster_id=config.databricks_cluster_id,
        emr_cluster_id=config.emr_cluster_id,
        jobs=jobs,
        skipped_tables=skipped_map,
    )


def _baseline_lock_for_key(job_key: str) -> threading.Lock:
    with _baseline_key_locks_guard:
        if job_key not in _baseline_key_locks:
            _baseline_key_locks[job_key] = threading.Lock()
        return _baseline_key_locks[job_key]


def _finalize_lock_for_key(job_key: str) -> threading.Lock:
    with _job_finalize_locks_guard:
        if job_key not in _job_finalize_locks:
            _job_finalize_locks[job_key] = threading.Lock()
        return _job_finalize_locks[job_key]


def _manifest_has_active_job(manifest: RunManifest, job_key: str) -> bool:
    """True when the same table already has a non-terminal in-flight job."""
    for existing in manifest.jobs:
        if existing.key != job_key:
            continue
        if existing.status in {"running", "baseline_done", "submitted", "emr_done"}:
            return True
    return False


def _pending_jobs_for_dag(
    manifest: RunManifest,
    domain: str,
    dag: str,
) -> List[ValidationJob]:
    """Return one pending job per table for a single DAG (batch manifests are multi-DAG)."""
    seen: set[str] = set()
    deduped: List[ValidationJob] = []
    for job in manifest.jobs:
        if job.domain != domain or job.dag != dag or job.status != "pending":
            continue
        if _manifest_has_active_job(manifest, job.key):
            continue
        if job.key in seen:
            continue
        seen.add(job.key)
        deduped.append(job)
    return deduped


def _find_job_in_manifest(manifest: RunManifest, job_key: str) -> Optional[ValidationJob]:
    for existing in manifest.jobs:
        if existing.key == job_key:
            return existing
    return None


def _load_metadata_column_names(
    domain: str,
    dag: str,
    layer: str,
    table: str,
    repo_root: Optional[Path],
) -> List[str]:
    root = repo_root or Path.cwd()
    meta_path = root / "dags" / domain / dag / "metadata" / layer / f"{table}.yml"
    if not meta_path.is_file():
        return []
    with meta_path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    columns = data.get("columns") or {}
    if isinstance(columns, dict):
        return [str(name) for name in columns.keys()]
    return []


def _describe_working_tree_schema(
    config: SubmitConfig,
    job: ValidationJob,
    db_cluster_id: str,
) -> List[SchemaEntry]:
    """Fast DESCRIBE on working-tree SQL (no COUNT) for sample order_by resolution."""
    pinned_sql = load_pinned_sql(
        job.domain,
        job.dag,
        job.layer,
        job.table,
        config.load_start_date,
        config.load_end_date,
        git_ref=None,
        repo_root=config.repo_root,
    )
    db_api = DatabricksAPI(
        config.databricks_profile, db_cluster_id, timeout_sec=config.timeout_sec
    )
    with _db_context_lock:
        if not db_api.open_context():
            return []
        try:
            describe_result = db_api.execute_sql(build_describe_query(pinned_sql))
            return _schema_from_describe(describe_result.row_dicts)
        finally:
            db_api.close_context()


def resolve_emr_order_by(
    config: SubmitConfig,
    job: ValidationJob,
    db_cluster_id: str,
) -> tuple[str, bool]:
    """Return (order_by_clause, parallel_safe).

    When parallel_safe is False and skip_sample is off, submit falls back to coupled
    baseline-then-EMR for that table so sample ORDER BY matches master SQL.
    """
    z_order = get_z_order_by(job.domain, job.dag, job.table, config.repo_root)
    if z_order:
        return format_order_by_clause(z_order), True

    meta_cols = _load_metadata_column_names(
        job.domain, job.dag, job.layer, job.table, config.repo_root
    )
    if meta_cols:
        schema: List[SchemaEntry] = [(name, "string") for name in meta_cols]
        resolved = resolve_order_by_cols(
            job.table, schema, job.domain, job.dag, config.repo_root
        )
        positional = [str(position) for position in range(1, min(len(schema), 3) + 1)]
        if resolved and resolved != positional:
            return format_order_by_clause(resolved), True

    if config.skip_sample:
        return "1,2,3", True

    schema = _describe_working_tree_schema(config, job, db_cluster_id)
    if schema:
        resolved = resolve_order_by_cols(
            job.table, schema, job.domain, job.dag, config.repo_root
        )
        return format_order_by_clause(resolved), True

    return "1,2,3", False


def _merge_job_errors(job: ValidationJob, new_errors: List[str]) -> None:
    if not new_errors:
        return
    merged = "; ".join(new_errors)
    job.error = f"{job.error}; {merged}" if job.error else merged


def _finalize_decoupled_job_status(job: ValidationJob, side_errors: List[str]) -> None:
    if job.status == "manual_check":
        return
    if side_errors:
        _merge_job_errors(job, side_errors)
        if not job.error:
            job.error = "; ".join(side_errors)
        job.status = "error"
        job.verdict = "FAIL"
        job.completed_at = _utc_now_iso()
    elif job.baseline_done_at and job.emr_step_id:
        job.status = "running"
    elif job.emr_step_id:
        job.status = "running"
    elif job.baseline_done_at:
        job.status = "baseline_done"


def _run_baseline_task(
    config: SubmitConfig,
    manifest: RunManifest,
    job_key: str,
    db_cluster_id: str,
    stager: SqlStager,
) -> List[str]:
    job = _find_job_in_manifest(manifest, job_key)
    if job is None:
        return [f"job missing from manifest: {job_key}"]

    errors: List[str] = []
    try:
        baseline, baseline_error = _capture_baseline_for_job(
            config, job, db_cluster_id, manifest=manifest
        )
        job = _find_job_in_manifest(manifest, job_key) or job
        if baseline_error:
            if is_manual_check_error(baseline_error):
                job.status = "manual_check"
                job.verdict = "MANUAL_CHECK"
                job.error = manual_check_message(baseline_error)
                job.completed_at = _utc_now_iso()
                update_job(manifest, job, emr_env=config.emr_env)
                logger.warning(
                    "Manual check (baseline): %s — %s",
                    job.table_label,
                    job.error,
                )
                return errors
            errors.append(f"baseline: {baseline_error}")
            upload_text_to_s3(
                stager.log_uri_for(job.domain, job.dag, job.layer, job.table),
                baseline_error,
                emr_env=config.emr_env,
            )
        else:
            job.baseline_done_at = _utc_now_iso()
            update_job(manifest, job, emr_env=config.emr_env)
    except Exception as exc:
        errors.append(f"baseline: {exc}")
        logger.exception("Baseline task failed for %s", job_key)

    with _finalize_lock_for_key(job_key):
        job = _find_job_in_manifest(manifest, job_key) or job
        _finalize_decoupled_job_status(job, errors)
        update_job(manifest, job, emr_env=config.emr_env)
    return errors


def _run_emr_task(
    config: SubmitConfig,
    manifest: RunManifest,
    job_key: str,
    emr_cluster_id: str,
    db_cluster_id: str,
    stager: SqlStager,
) -> List[str]:
    job = _find_job_in_manifest(manifest, job_key)
    if job is None:
        return [f"job missing from manifest: {job_key}"]

    errors: List[str] = []
    try:
        order_by, _ = resolve_emr_order_by(config, job, db_cluster_id)
        pinned_sql = load_pinned_sql(
            job.domain,
            job.dag,
            job.layer,
            job.table,
            config.load_start_date,
            config.load_end_date,
            git_ref=None,
            repo_root=config.repo_root,
        )
        step_id, emr_error = _submit_emr_for_job(
            config,
            job,
            emr_cluster_id,
            order_by,
            pinned_sql,
            stager,
        )
        job = _find_job_in_manifest(manifest, job_key) or job
        if emr_error:
            errors.append(f"emr: {emr_error}")
        else:
            job.emr_step_id = step_id or ""
            job.emr_submitted_at = _utc_now_iso()
            update_job(manifest, job, emr_env=config.emr_env)
    except Exception as exc:
        errors.append(f"emr: {exc}")
        logger.exception("EMR task failed for %s", job_key)

    with _finalize_lock_for_key(job_key):
        job = _find_job_in_manifest(manifest, job_key) or job
        if job.status != "manual_check":
            _finalize_decoupled_job_status(job, errors)
        update_job(manifest, job, emr_env=config.emr_env)
    return errors


def _capture_baseline_for_job(
    config: SubmitConfig,
    job: ValidationJob,
    db_cluster_id: str,
    manifest: Optional[RunManifest] = None,
) -> tuple[Optional[object], Optional[str]]:
    """Capture Databricks baseline; returns (TableBaseline, error)."""
    if manifest is not None:
        for sibling in manifest.jobs:
            if sibling.key == job.key and sibling.baseline_done_at and sibling is not job:
                cached = load_baseline_for_table(job.domain, job.dag, job.table, job.layer)
                if cached:
                    save_baseline_files(
                        cached, job.domain, s3_uri=job.baseline_s3_uri, emr_env=config.emr_env
                    )
                    return cached, None

    with _baseline_lock_for_key(job.key):
        if job.key in _baseline_capture_cache:
            return _baseline_capture_cache[job.key]

        existing = load_baseline_for_table(job.domain, job.dag, job.table, job.layer)
        if existing and is_baseline_fresh(
            existing,
            config.load_start_date,
            config.load_end_date,
            domain=job.domain,
            git_ref=config.baseline_git_ref,
            repo_root=config.repo_root,
        ):
            save_baseline_files(
                existing, job.domain, s3_uri=job.baseline_s3_uri, emr_env=config.emr_env
            )
            result = (existing, None)
            _baseline_capture_cache[job.key] = result
            return result

        db_api = DatabricksAPI(
            config.databricks_profile, db_cluster_id, timeout_sec=config.timeout_sec
        )
        with _db_context_lock:
            if not db_api.open_context():
                result = (None, "Failed to open Databricks SQL context")
                _baseline_capture_cache[job.key] = result
                return result
            try:
                capture = DatabricksBaseline(
                    db_api=db_api,
                    dag_name=job.dag,
                    domain=job.domain,
                    load_start_date=config.load_start_date,
                    load_end_date=config.load_end_date,
                    git_ref=config.baseline_git_ref,
                    sample_limit=config.sample_limit,
                    skip_sample=config.skip_sample,
                    skip_profile=config.skip_profile,
                    table_filter=job.table,
                    layer_filter=job.layer,
                    repo_root=config.repo_root,
                )
                baseline = capture.capture_table_baseline(job.table, job.layer)
            finally:
                db_api.close_context()

        save_baseline_files(
            baseline, job.domain, s3_uri=job.baseline_s3_uri, emr_env=config.emr_env
        )
        if baseline.error:
            result = (baseline, baseline.error)
        else:
            result = (baseline, None)
        _baseline_capture_cache[job.key] = result
        return result


def _submit_emr_for_job(
    config: SubmitConfig,
    job: ValidationJob,
    emr_cluster_id: str,
    order_by: str,
    pinned_sql: str,
    stager: SqlStager,
) -> tuple[Optional[str], Optional[str]]:
    """Stage SQL and submit EMR step without waiting. Returns (step_id, error)."""
    ensure_aws_credentials(config.emr_env)
    sql_s3_uri = stager.stage_sql(
        pinned_sql,
        job.domain,
        job.dag,
        job.layer,
        job.table,
    )
    cmd = [
        "submit-step",
        "--cluster-id",
        emr_cluster_id,
        "--step-name",
        f"migration-validate-{job.dag}-{job.layer}-{job.table}",
        "--uri",
        VALIDATE_JOB_REL,
        "--job-arg",
        "--sql-s3-uri",
        "--job-arg",
        sql_s3_uri,
        "--job-arg",
        "--result-s3-uri",
        "--job-arg",
        job.emr_s3_uri,
        "--job-arg",
        "--order-by",
        "--job-arg",
        order_by,
        "--job-arg",
        "--sample-limit",
        "--job-arg",
        str(config.sample_limit),
        "--no-wait",
        "--deploy-mode",
        "client",
        "--action-on-failure",
        "CONTINUE",
    ]
    if config.skip_sample:
        cmd.extend(["--job-arg", "--skip-sample"])
    if config.skip_profile:
        cmd.extend(["--job-arg", "--skip-profile"])

    returncode, output = run_emr_cli(cmd, emr_env=config.emr_env, quiet=True)
    if returncode != 0:
        return None, output.strip() or f"migration-emr-cli submit-step failed ({returncode})"
    step_id = parse_step_id_from_output(output)
    if not step_id:
        return None, f"Missing StepId in migration-emr-cli output: {output[:200]}"
    return step_id, None


def _submit_single_job_coupled(
    config: SubmitConfig,
    manifest: RunManifest,
    job: ValidationJob,
    db_cluster_id: str,
    emr_cluster_id: str,
    stager: SqlStager,
) -> ValidationJob:
    job = ensure_job_uris(manifest, job, stager=stager)
    job.submitted_at = _utc_now_iso()
    job.status = "submitted"
    errors: List[str] = []

    try:
        baseline, baseline_error = _capture_baseline_for_job(
            config, job, db_cluster_id, manifest=manifest
        )
        if baseline_error:
            if is_manual_check_error(baseline_error):
                job.status = "manual_check"
                job.verdict = "MANUAL_CHECK"
                job.error = manual_check_message(baseline_error)
                job.completed_at = _utc_now_iso()
                update_job(manifest, job, emr_env=config.emr_env)
                logger.warning(
                    "Manual check (baseline): %s — %s",
                    job.table_label,
                    job.error,
                )
                return job
            errors.append(f"baseline: {baseline_error}")
            upload_text_to_s3(
                stager.log_uri_for(job.domain, job.dag, job.layer, job.table),
                baseline_error,
                emr_env=config.emr_env,
            )
        else:
            job.baseline_done_at = _utc_now_iso()
            job.status = "baseline_done"

        order_by = "1,2,3"
        if baseline and not baseline_error:
            typed = baseline if isinstance(baseline, TableBaseline) else None
            if typed and typed.schema:
                order_by = format_order_by_clause(
                    typed.order_by_cols
                    or resolve_order_by_cols(
                        job.table,
                        typed.schema,
                        job.domain,
                        job.dag,
                        config.repo_root,
                    )
                )
            pin_start = config.load_start_date
            pin_end = config.load_end_date
            pinned_sql = load_pinned_sql(
                job.domain,
                job.dag,
                job.layer,
                job.table,
                pin_start,
                pin_end,
                git_ref=None,
                repo_root=config.repo_root,
            )
            step_id, emr_error = _submit_emr_for_job(
                config,
                job,
                emr_cluster_id,
                order_by,
                pinned_sql,
                stager,
            )
            if emr_error:
                errors.append(f"emr: {emr_error}")
            else:
                job.emr_step_id = step_id or ""
                job.emr_submitted_at = _utc_now_iso()
                if job.status == "baseline_done":
                    job.status = "running"
                elif not errors:
                    job.status = "running"
    except Exception as exc:
        errors.append(str(exc))
        logger.exception("Submit failed for %s", job.table_label)

    if errors:
        job.status = "error"
        job.verdict = "FAIL"
        job.error = "; ".join(errors)
        job.completed_at = _utc_now_iso()
    elif job.status in {"baseline_done", "running", "submitted"}:
        job.status = "running"

    update_job(manifest, job, emr_env=config.emr_env)
    logger.info("Submitted %s → %s", job.table_label, job.status)
    return job


def apply_submit_config_to_manifest(
    manifest: RunManifest,
    config: SubmitConfig,
) -> None:
    """Refresh manifest-level metadata from the current submit (resume-safe)."""
    manifest.load_start_date = config.load_start_date
    manifest.load_end_date = config.load_end_date
    manifest.baseline_git_ref = config.baseline_git_ref
    manifest.databricks_cluster_id = config.databricks_cluster_id
    manifest.emr_cluster_id = config.emr_cluster_id


def run_submit(config: SubmitConfig) -> RunManifest:
    """Fire parallel Databricks baselines and EMR steps; persist manifest to S3."""
    if not config.databricks_cluster_id:
        raise RuntimeError(
            "Databricks cluster id is required. Pass --cluster with a running "
            "all-purpose cluster id (job-* clusters are rejected)."
        )
    config.databricks_cluster_id = resolve_databricks_cluster(
        config.databricks_cluster_id,
        config.databricks_profile,
    )
    ensure_aws_credentials(config.emr_env)
    emr_candidate: Optional[str] = config.emr_cluster_id or None
    if config.new_emr_session:
        emr_candidate = None
    elif emr_candidate:
        reusable, state = is_emr_cluster_reusable(emr_candidate)
        if not reusable:
            logger.warning(
                "Session EMR cluster %s not reusable (%s) — resolving a new one",
                emr_candidate,
                state,
            )
            emr_candidate = None
    config.emr_cluster_id = resolve_validation_emr_cluster(
        emr_candidate,
        emr_env=config.emr_env,
        new_session=config.new_emr_session,
        allow_create=config.allow_create_emr,
    )

    dag_manifest = build_manifest_for_dag(config)
    try:
        existing = load_manifest(dag_manifest.run_id, emr_env=config.emr_env)
        existing_keys = {job.key for job in existing.jobs}
        for job in dag_manifest.jobs:
            if job.key not in existing_keys:
                existing.jobs.append(job)
        existing.skipped_tables.update(dag_manifest.skipped_tables)
        manifest = existing
    except FileNotFoundError:
        manifest = dag_manifest
    manifest.jobs = dedupe_manifest_jobs(manifest.jobs)
    apply_submit_config_to_manifest(manifest, config)
    save_manifest(manifest, emr_env=config.emr_env)

    stager = SqlStager(
        run_id=manifest.run_id,
        staging_uri=config.staging_uri,
        emr_env=config.emr_env,
    )

    session = load_session()
    session["active_run_id"] = manifest.run_id
    session["manifest_s3_uri"] = manifest.manifest_s3_uri
    session["databricks_cluster_id"] = config.databricks_cluster_id
    session["emr_cluster_id"] = config.emr_cluster_id
    save_session(session)

    pending_jobs = _pending_jobs_for_dag(manifest, config.domain, config.dag)
    if not pending_jobs:
        logger.warning("No pending jobs to submit for %s/%s", config.domain, config.dag)
        return manifest

    for job in pending_jobs:
        job = ensure_job_uris(manifest, job, stager=stager)
        job.submitted_at = _utc_now_iso()
        job.status = "submitted"
        update_job(manifest, job, emr_env=config.emr_env)

    parallel_jobs: List[ValidationJob] = []
    coupled_jobs: List[ValidationJob] = []
    for job in pending_jobs:
        _, parallel_safe = resolve_emr_order_by(
            config, job, config.databricks_cluster_id
        )
        if config.skip_sample or parallel_safe:
            parallel_jobs.append(job)
        else:
            coupled_jobs.append(job)
            logger.info(
                "Coupled submit (sample order_by): %s — await baseline before EMR",
                job.table_label,
            )

    db_workers = min(config.max_parallel_databricks, max(len(parallel_jobs), 1))
    emr_workers = min(config.max_parallel_emr, max(len(parallel_jobs), 1))
    logger.info(
        "Submitting %s job(s) for %s/%s (run_id=%s, decoupled=%s coupled=%s, "
        "db_workers=%s emr_workers=%s)",
        len(pending_jobs),
        config.domain,
        config.dag,
        manifest.run_id,
        len(parallel_jobs),
        len(coupled_jobs),
        db_workers,
        emr_workers,
    )

    if parallel_jobs:
        with ThreadPoolExecutor(max_workers=db_workers) as db_pool, ThreadPoolExecutor(
            max_workers=emr_workers
        ) as emr_pool:
            futures = []
            for job in parallel_jobs:
                futures.append(
                    db_pool.submit(
                        _run_baseline_task,
                        config,
                        manifest,
                        job.key,
                        config.databricks_cluster_id,
                        stager,
                    )
                )
                futures.append(
                    emr_pool.submit(
                        _run_emr_task,
                        config,
                        manifest,
                        job.key,
                        config.emr_cluster_id,
                        config.databricks_cluster_id,
                        stager,
                    )
                )
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as exc:
                    logger.error("Decoupled submit worker failed: %s", exc)

    if coupled_jobs:
        coupled_workers = min(config.max_parallel, len(coupled_jobs))
        with ThreadPoolExecutor(max_workers=coupled_workers) as executor:
            futures = {
                executor.submit(
                    _submit_single_job_coupled,
                    config,
                    manifest,
                    job,
                    config.databricks_cluster_id,
                    config.emr_cluster_id,
                    stager,
                ): job
                for job in coupled_jobs
            }
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as exc:
                    job = futures[future]
                    job.status = "error"
                    job.error = str(exc)
                    job.completed_at = _utc_now_iso()
                    update_job(manifest, job, emr_env=config.emr_env)
                    logger.error("Coupled submit failed for %s: %s", job.table_label, exc)

    for job in pending_jobs:
        refreshed = _find_job_in_manifest(manifest, job.key)
        if refreshed:
            logger.info("Submitted %s → %s", refreshed.table_label, refreshed.status)

    save_manifest(manifest, emr_env=config.emr_env)
    counts = manifest.counts()
    logger.info(
        "Submit complete run_id=%s manifest=%s jobs=%s running=%s error=%s",
        manifest.run_id,
        manifest.manifest_s3_uri,
        counts["total"],
        counts["running"] + counts["baseline_done"] + counts["submitted"],
        counts["error"],
    )
    return manifest


def merge_manifests(manifests: List[RunManifest]) -> RunManifest:
    """Combine per-DAG manifests into one batch manifest (same run_id required)."""
    if not manifests:
        raise ValueError("No manifests to merge")
    base = manifests[0]
    jobs: List[ValidationJob] = []
    skipped = dict(base.skipped_tables)
    for other in manifests:
        if other.run_id != base.run_id:
            raise ValueError("Cannot merge manifests with different run_ids")
        jobs.extend(other.jobs)
        skipped.update(other.skipped_tables)
    base.jobs = dedupe_manifest_jobs(jobs)
    base.skipped_tables = skipped
    return base
