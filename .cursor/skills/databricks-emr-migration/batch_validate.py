#!/usr/bin/env python3
"""Multi-DAG async validation for line-scope EMR migration."""

from __future__ import annotations

import argparse
import logging
import sys
import uuid
from datetime import date, timedelta
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent
if str(SKILL_DIR) not in sys.path:
    sys.path.insert(0, str(SKILL_DIR))

from async_runner import SubmitConfig, run_submit
from baseline import TableScopeKey, baseline_lookup_key
from cluster_bootstrap import load_session, save_session
from dag_discovery import (
    discover_dags_by_names,
    discover_dags_for_line,
    load_scope_file,
    parse_scope_pairs,
)
from manifest import RunManifest, load_manifest, reset_stale_jobs, save_manifest
from paths import REPO_ROOT
from poller import WatchConfig, run_watch, spawn_detached_watch
from report import finalize_dag_reports, print_batch_gate_summary, watch_has_syntax_failures
from sql_lint import discover_tables_needing_translation

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Batch async EMR migration validation")
    parser.add_argument("--line", help="Business line folder under dags/ (e.g. fintech)")
    parser.add_argument("--dags", help="Comma-separated DAG names (requires --line as domain)")
    parser.add_argument(
        "--scope",
        help="Comma-separated domain/dag pairs (e.g. agents/enrich_agent,fintech/enrich_billing)",
    )
    parser.add_argument(
        "--scope-file",
        help="YAML file listing domain/dag pairs for multi-domain batch scope",
    )
    parser.add_argument(
        "--phase",
        choices=["submit", "watch", "compare"],
        default="compare",
        help="submit, watch, or compare (submit + watch)",
    )
    parser.add_argument("--run-id", help="Existing run id for watch/compare resume")
    parser.add_argument(
        "--cluster",
        required=False,
        help="Databricks all-purpose cluster id (required for submit/compare)",
    )
    parser.add_argument("--profile", default="PROD")
    parser.add_argument("--emr-env", default="prod")
    parser.add_argument("--staging-uri")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument(
        "--with-sample",
        action="store_true",
        help="Also capture and compare deterministic sample (default: schema + count only)",
    )
    parser.add_argument(
        "--no-profile",
        action="store_true",
        help="Legacy schema + count only (skip null counts and checksum profile)",
    )
    parser.add_argument("--new-emr-session", action="store_true")
    parser.add_argument("--no-create-emr", action="store_true")
    parser.add_argument("--max-parallel", type=int, default=5)
    parser.add_argument("--poll-interval", type=int, default=15)
    parser.add_argument("--job-timeout", type=int, default=3600)
    parser.add_argument("--manual-check-timeout", type=int, default=300)
    parser.add_argument("--global-timeout", type=int)
    parser.add_argument("--detach", action="store_true")
    parser.add_argument("--no-detach", action="store_true")
    parser.add_argument(
        "--reset-stale",
        action="store_true",
        help="Reset stuck in-flight jobs to pending before submit",
    )
    parser.add_argument("--git-ref", default="master")
    return parser.parse_args()


def _resolve_dag_list(args: argparse.Namespace) -> list[tuple[str, str]]:
    if args.scope_file:
        return load_scope_file(Path(args.scope_file), repo_root=REPO_ROOT)
    if args.scope:
        return parse_scope_pairs(args.scope, repo_root=REPO_ROOT)
    if args.dags:
        if not args.line:
            raise ValueError("--line (domain) is required with --dags")
        names = [name.strip() for name in args.dags.split(",") if name.strip()]
        return discover_dags_by_names(args.line, names, repo_root=REPO_ROOT)
    if args.line:
        return discover_dags_for_line(args.line, repo_root=REPO_ROOT)
    raise ValueError("Provide --scope-file, --scope, --line, or --dags with --line")


def _submitted_dag_keys(run_id: str, *, emr_env: str) -> set[tuple[str, str]]:
    try:
        manifest = load_manifest(run_id, emr_env=emr_env)
    except FileNotFoundError:
        return set()
    dag_keys = {(job.domain, job.dag) for job in manifest.jobs}
    dags_with_pending = {
        (job.domain, job.dag) for job in manifest.jobs if job.status == "pending"
    }
    return dag_keys - dags_with_pending


def _maybe_reset_stale(run_id: str, *, emr_env: str) -> None:
    try:
        manifest = load_manifest(run_id, emr_env=emr_env)
    except FileNotFoundError:
        logger.info("No manifest yet for run_id=%s — nothing to reset", run_id)
        return
    reset_count = reset_stale_jobs(manifest)
    if reset_count:
        save_manifest(manifest, emr_env=emr_env)
        logger.info("Reset %s stale in-flight job(s) to pending", reset_count)


def _run_batch_submit(args: argparse.Namespace, dag_list: list[tuple[str, str]]) -> str:
    load_start = str(date.today() - timedelta(days=1))
    load_end = str(date.today())
    run_id = args.run_id or uuid.uuid4().hex
    session = load_session()

    if args.reset_stale:
        _maybe_reset_stale(run_id, emr_env=args.emr_env)

    done = _submitted_dag_keys(run_id, emr_env=args.emr_env)
    if done:
        logger.info("Resuming run_id=%s — %s DAG(s) already in manifest", run_id, len(done))

    last_manifest = None  # type: Optional[RunManifest]
    submitted = 0
    skipped = 0
    for domain, dag_name in dag_list:
        if (domain, dag_name) in done:
            logger.info("Skipping %s/%s — already in manifest", domain, dag_name)
            skipped += 1
            continue

        translated, skipped_tables = discover_tables_needing_translation(
            domain,
            dag_name,
            args.git_ref,
            repo_root=REPO_ROOT,
        )
        allowlist: set[TableScopeKey] = {
            baseline_lookup_key(layer, table_name) for table_name, layer in translated
        }
        skipped_names = sorted(f"{layer}/{table}" for table, layer in skipped_tables)
        if not allowlist:
            logger.info("Skipping %s/%s — no tables need translation", domain, dag_name)
            finalize_dag_reports(
                domain,
                dag_name,
                [],
                load_start_date=load_start,
                load_end_date=load_end,
                skipped_tables=skipped_names,
            )
            continue
        config = SubmitConfig(
            domain=domain,
            dag=dag_name,
            load_start_date=load_start,
            load_end_date=load_end,
            baseline_git_ref=args.git_ref,
            databricks_profile=args.profile,
            databricks_cluster_id=args.cluster or "",
            emr_cluster_id=str(session.get("emr_cluster_id") or ""),
            emr_env=args.emr_env,
            staging_uri=args.staging_uri,
            skip_sample=args.skip_sample,
            skip_profile=args.skip_profile,
            timeout_sec=args.timeout,
            table_allowlist=allowlist,
            repo_root=REPO_ROOT,
            max_parallel=args.max_parallel,
            allow_create_emr=not args.no_create_emr,
            new_emr_session=args.new_emr_session and submitted == 0,
            run_id=run_id,
            skipped_tables=skipped_names,
        )
        last_manifest = run_submit(config)
        submitted += 1
        session = load_session()

    if last_manifest is None:
        if skipped and not submitted:
            logger.info("All DAGs already submitted for run_id=%s", run_id)
            session["active_run_id"] = run_id
            save_session(session)
        else:
            logger.warning("No DAGs submitted")
        print(f"run_id={run_id}")
        return run_id

    session["active_run_id"] = run_id
    session["manifest_s3_uri"] = last_manifest.manifest_s3_uri
    save_session(session)

    print(f"run_id={run_id}")
    print(f"manifest={last_manifest.manifest_s3_uri}")
    print(f"jobs={len(last_manifest.jobs)}")
    print(f"dags_submitted={submitted}")
    print(f"dags_skipped={skipped}")
    return run_id


def _run_watch(args: argparse.Namespace) -> int:
    run_id = args.run_id or str(load_session().get("active_run_id") or "")
    if not run_id:
        logger.error("watch requires --run-id")
        return 1
    config = WatchConfig(
        run_id=run_id,
        emr_env=args.emr_env,
        poll_interval_sec=args.poll_interval,
        job_timeout_sec=args.job_timeout,
        manual_check_timeout_sec=args.manual_check_timeout,
        global_timeout_sec=args.global_timeout,
        skip_sample=args.skip_sample,
        skip_profile=args.skip_profile,
    )
    _, dag_results = run_watch(config)
    if dag_results:
        print_batch_gate_summary(dag_results)
    return 0 if not watch_has_syntax_failures(dag_results) else 1


def main() -> int:
    args = parse_args()
    args.skip_sample = not args.with_sample
    args.skip_profile = args.no_profile

    if args.phase == "watch":
        return _run_watch(args)

    if args.phase in {"submit", "compare"} and not args.cluster:
        logger.error(
            "--cluster is required (running Databricks all-purpose cluster id). "
            "Ask the user for a cluster id before batch submit/compare."
        )
        return 1

    try:
        dag_list = _resolve_dag_list(args)
    except (ValueError, FileNotFoundError) as exc:
        logger.error("%s", exc)
        return 1

    logger.info("Batch scope: %s DAG(s)", len(dag_list))
    run_id = _run_batch_submit(args, dag_list)

    if args.phase == "submit":
        return 0

    args.run_id = run_id
    if args.detach and not args.no_detach:
        pid, log_path = spawn_detached_watch(
            run_id,
            emr_env=args.emr_env,
            poll_interval_sec=args.poll_interval,
            job_timeout_sec=args.job_timeout,
            manual_check_timeout_sec=args.manual_check_timeout,
            skip_profile=args.skip_profile,
            skip_sample=args.skip_sample,
        )
        print(f"watcher_pid={pid}")
        print(f"log={log_path}")
        return 0

    return _run_watch(args)


if __name__ == "__main__":
    sys.exit(main())
