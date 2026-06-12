#!/usr/bin/env python3
"""Reset FAIL (syntax by default) jobs and re-submit once each, then watch."""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SKILL_DIR))

from async_runner import SubmitConfig, run_submit
from baseline import baseline_lookup_key
from cluster_bootstrap import _save_validation_session, load_session
from emr_runner import SqlStager, delete_s3_object
from failure_classifier import is_emr_syntax_failure, is_infra_failure
from manifest import dedupe_manifest_jobs, load_manifest, reset_stale_jobs, save_manifest
from poller import WatchConfig, run_watch, spawn_detached_watch
from report import watch_has_syntax_failures

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

REPO_ROOT = SKILL_DIR.parents[2]


def _reset_job_fields(job) -> None:
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


def _clear_stale_artifacts(job, stager: SqlStager, *, emr_env: str) -> None:
    """Remove prior validation JSON so watch does not compare stale S3 payloads."""
    for uri in (
        job.baseline_s3_uri,
        job.emr_s3_uri,
        stager.emr_result_uri_for(job.domain, job.dag, job.layer, job.table),
        stager.legacy_emr_result_uri_for(job.domain, job.dag, job.layer, job.table),
        stager.baseline_uri_for(job.domain, job.dag, job.layer, job.table),
    ):
        delete_s3_object(uri, emr_env=emr_env)


def _should_revalidate(job, *, all_failures: bool, force_infra: bool) -> tuple[bool, str]:
    if is_infra_failure(job.error) and not force_infra:
        return False, "infra"
    if not all_failures and not is_emr_syntax_failure(job.error):
        return False, "parity"
    return True, ""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument(
        "--verdict",
        default="FAIL",
        help="Comma-separated verdicts to revalidate (default: FAIL)",
    )
    parser.add_argument("--databricks-cluster", default="0410-141554-z6c4r6hp")
    parser.add_argument("--emr-cluster", help="Reuse this EMR validation cluster id")
    parser.add_argument("--emr-env", default="prod")
    parser.add_argument("--detach-watch", action="store_true")
    parser.add_argument(
        "--all-failures",
        action="store_true",
        help="Revalidate all FAIL jobs (default: EMR syntax FAILs only)",
    )
    parser.add_argument(
        "--force-infra",
        action="store_true",
        help="Re-submit tables that failed with S3/IAM AccessDenied",
    )
    parser.add_argument(
        "--reset-stale",
        action="store_true",
        help="Reset stuck in-flight jobs to pending before revalidation",
    )
    parser.add_argument("--submit-only", action="store_true")
    args = parser.parse_args()

    verdicts = {v.strip().upper() for v in args.verdict.split(",") if v.strip()}
    manifest = load_manifest(args.run_id, emr_env=args.emr_env)

    if args.reset_stale:
        reset_count = reset_stale_jobs(manifest)
        if reset_count:
            save_manifest(manifest, emr_env=args.emr_env)
            logger.info("Reset %s stale in-flight job(s) to pending", reset_count)

    targets = [job for job in manifest.jobs if (job.verdict or "").upper() in verdicts]
    already_pending = [job for job in manifest.jobs if job.status == "pending"]
    if not targets and not already_pending:
        logger.info("No jobs with verdict in %s and no pending — nothing to do", sorted(verdicts))
        return 0

    if args.emr_cluster:
        _save_validation_session(args.emr_cluster.strip(), args.emr_env)
        logger.info("Using EMR cluster from --emr-cluster: %s", args.emr_cluster.strip())

    skipped_infra = 0
    skipped_parity = 0
    reset_count = 0
    stager = SqlStager(run_id=args.run_id, emr_env=args.emr_env)
    for job in manifest.jobs:
        if job not in targets:
            continue
        ok, skip_kind = _should_revalidate(
            job,
            all_failures=args.all_failures,
            force_infra=args.force_infra,
        )
        if not ok:
            if skip_kind == "infra":
                job.status = "manual_check"
                job.error = (job.error or "") + " [infra: skipped revalidate]"
                skipped_infra += 1
                logger.warning("Skipping infra failure (use --force-infra to retry): %s", job.key)
            else:
                skipped_parity += 1
                logger.warning(
                    "Skipping parity failure (not retryable; use --all-failures): %s",
                    job.key,
                )
            continue
        _clear_stale_artifacts(job, stager, emr_env=args.emr_env)
        _reset_job_fields(job)
        reset_count += 1

    manifest.jobs = dedupe_manifest_jobs(manifest.jobs)
    save_manifest(manifest, emr_env=args.emr_env)
    logger.info(
        "Reset %s job(s) for revalidation (%s infra skipped, %s parity skipped)",
        reset_count,
        skipped_infra,
        skipped_parity,
    )

    load_start = manifest.load_start_date
    load_end = manifest.load_end_date
    pending = [job for job in manifest.jobs if job.status == "pending"]
    logger.info("Submitting %s table(s)", len(pending))

    emr_cluster_id = (args.emr_cluster or "").strip() or str(load_session().get("emr_cluster_id") or "")
    for job in pending:
        logger.info("Submit %s", job.key)
        config = SubmitConfig(
            domain=job.domain,
            dag=job.dag,
            load_start_date=load_start,
            load_end_date=load_end,
            baseline_git_ref=manifest.baseline_git_ref,
            databricks_profile="PROD",
            databricks_cluster_id=args.databricks_cluster,
            emr_cluster_id=emr_cluster_id,
            emr_env=args.emr_env,
            skip_sample=True,
            timeout_sec=300,
            table_filter=job.table,
            table_allowlist={baseline_lookup_key(job.layer, job.table)},
            repo_root=REPO_ROOT,
            max_parallel=5,
            max_parallel_databricks=3,
            max_parallel_emr=8,
            run_id=args.run_id,
            new_emr_session=False,
        )
        try:
            run_submit(config)
        except Exception as exc:
            logger.error("Submit failed for %s: %s", job.key, exc)

    if args.submit_only:
        logger.info("Submit-only complete")
        return 0

    if args.detach_watch:
        pid, log_path = spawn_detached_watch(args.run_id, emr_env=args.emr_env)
        logger.info("Detached watch pid=%s log=%s", pid, log_path)
        return 0

    config = WatchConfig(run_id=args.run_id, emr_env=args.emr_env)
    _, dag_results = run_watch(config)
    return 0 if not watch_has_syntax_failures(dag_results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
