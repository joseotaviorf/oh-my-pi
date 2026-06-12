#!/usr/bin/env python3
"""Databricks -> EMR migration validation CLI."""

from __future__ import annotations

import argparse
import logging
import sys
from datetime import date, timedelta
from pathlib import Path
from typing import Optional, Set

SKILL_DIR = Path(__file__).resolve().parent
if str(SKILL_DIR) not in sys.path:
    sys.path.insert(0, str(SKILL_DIR))

from async_runner import SubmitConfig, run_submit
from emr_runner import ensure_aws_credentials
from poller import WatchConfig, run_watch, spawn_detached_watch
from input_validation import InputValidationError, validate_cli_args, validate_git_ref, validate_iso_date
from baseline import (
    DatabricksBaseline,
    TableScopeKey,
    baseline_lookup_key,
    discover_tables,
    format_table_label,
    load_baselines,
    tables_needing_baseline,
)
from models import ValidationResult
from paths import REPO_ROOT
from cluster_bootstrap import (
    load_session,
    resolve_databricks_cluster,
    resolve_validation_emr_cluster,
    update_session_after_compare,
)
from databricks_client import DatabricksAPI
from emr_validation import EMRValidation
from report import (
    is_fully_skipped_dag,
    print_batch_gate_summary,
    print_compare_summary,
    syntax_failures,
    update_migration_summary,
    watch_has_syntax_failures,
    write_report,
)
from sql_lint import discover_tables_needing_translation

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Databricks -> EMR migration validation (compare = baseline + EMR + report)",
    )
    parser.add_argument("--dag", help="DAG name (e.g. dw_credit_analysis); optional for watch with --run-id")
    parser.add_argument("--domain", default="fintech", help="DAG domain folder")
    parser.add_argument("--profile", default="PROD", help="Databricks profile")
    parser.add_argument("--cluster", required=False, help="Running Databricks all-purpose cluster id (required for compare/submit)")
    parser.add_argument("--emr-cluster", help="EMR cluster id")
    parser.add_argument(
        "--phase",
        choices=["compare", "submit", "watch", "2", "4", "all"],
        default="compare",
        help="compare (default): async submit + watch + report; submit/watch for batch runs",
    )
    parser.add_argument("--run-id", help="Resume or watch an existing async validation run")
    parser.add_argument(
        "--sync",
        action="store_true",
        help="Legacy blocking sequential compare (debug)",
    )
    parser.add_argument(
        "--detach",
        action="store_true",
        help="After submit, spawn background watch subprocess and exit",
    )
    parser.add_argument(
        "--no-detach",
        action="store_true",
        help="Internal: run watch in foreground (used by detached worker)",
    )
    parser.add_argument("--poll-interval", type=int, default=15, help="S3 poll interval seconds")
    parser.add_argument("--job-timeout", type=int, default=3600, help="Per-table hard wall clock timeout")
    parser.add_argument(
        "--manual-check-timeout",
        type=int,
        default=300,
        help="Skip table and flag for manual review after this many seconds (default: 300)",
    )
    parser.add_argument("--global-timeout", type=int, help="Whole watch run ceiling seconds")
    parser.add_argument("--max-parallel", type=int, default=5, help="Parallel submit workers")
    parser.add_argument("--table", help="Validate a single table")
    parser.add_argument(
        "--git-ref",
        help="Git ref for Databricks baseline SQL (compare mode defaults to master)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=300,
        help="Databricks SQL timeout seconds; exceeded → manual check (default: 300)",
    )
    parser.add_argument("--emr-env", default="prod", help="EMR environment for emr-cli")
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
    parser.add_argument(
        "--all-tables",
        action="store_true",
        help="Compare all SQL files (default: only tables that needed translation on master)",
    )
    parser.add_argument(
        "--new-emr-session",
        action="store_true",
        help="Create a fresh emr-cli validation cluster (LogUri cli/)",
    )
    parser.add_argument(
        "--no-create-emr",
        action="store_true",
        help="Do not create EMR cluster; require an existing migration-validation session cluster",
    )
    parser.add_argument("--staging-uri", help="Override EMR SQL staging S3 prefix")
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Stream full EMR Spark logs to the terminal (default: quiet progress only)",
    )
    return parser.parse_args()


def _resolve_table_allowlist(
    args: argparse.Namespace,
    baseline_git_ref: str,
    repo_root: Path,
) -> tuple[Optional[Set[TableScopeKey]], list[str]]:
    if args.all_tables or args.phase in {"2", "4"}:
        return None, []
    if args.table:
        tables = discover_tables(args.domain, args.dag, args.table, repo_root=repo_root)
        return {
            baseline_lookup_key(layer, table_name) for table_name, layer in tables
        }, []

    translated, skipped = discover_tables_needing_translation(
        args.domain,
        args.dag,
        baseline_git_ref,
        repo_root=repo_root,
    )
    allowlist = {
        baseline_lookup_key(layer, table_name) for table_name, layer in translated
    }
    skipped_names = sorted(
        f"{layer}/{table_name}" for table_name, layer in skipped
    )
    logger.info(
        "Translation scope: %s table(s) to validate, %s skipped (EMR-compatible on %s)",
        len(allowlist),
        len(skipped_names),
        baseline_git_ref,
    )
    if skipped_names:
        logger.info("Skipped (no translation needed): %s", ", ".join(skipped_names))
    return allowlist, skipped_names


def _baseline_failure_keys(
    baseline_failure_results: list[ValidationResult],
) -> Set[TableScopeKey]:
    keys: Set[TableScopeKey] = set()
    for result in baseline_failure_results:
        if "/" not in result.table:
            continue
        layer, table_name = result.table.split("/", 1)
        keys.add(baseline_lookup_key(layer, table_name))
    return keys


def _emr_table_allowlist(
    domain: str,
    dag_name: str,
    table_filter: str | None,
    table_allowlist: Optional[Set[TableScopeKey]],
    failed_keys: Set[TableScopeKey],
    repo_root: Path,
) -> Optional[Set[TableScopeKey]]:
    if not failed_keys:
        return table_allowlist
    if table_allowlist is None:
        scope = {
            baseline_lookup_key(layer, table_name)
            for table_name, layer in discover_tables(
                domain,
                dag_name,
                table_filter,
                repo_root=repo_root,
            )
        }
    else:
        scope = set(table_allowlist)
    scope -= failed_keys
    return scope


def _validation_result_for_baseline_failure(
    layer: str,
    table_name: str,
    message: str,
) -> ValidationResult:
    return ValidationResult(
        table=format_table_label(layer, table_name),
        baseline_count=0,
        emr_count=0,
        count_delta_pct=0.0,
        schema_match=False,
        schema_issues=[message],
        sample_match=False,
        sample_diff_rows=[],
        status="FAIL",
        message=message,
    )


def _validation_results_for_workflow_error(
    domain: str,
    dag_name: str,
    message: str,
    *,
    table_filter: Optional[str] = None,
    table_allowlist: Optional[Set[TableScopeKey]] = None,
    exclude_keys: Optional[Set[TableScopeKey]] = None,
    repo_root: Path = REPO_ROOT,
) -> list[ValidationResult]:
    try:
        tables = discover_tables(domain, dag_name, table_filter, repo_root=repo_root)
    except FileNotFoundError:
        tables = []
    if table_allowlist is not None:
        tables = [
            (table_name, layer)
            for table_name, layer in tables
            if baseline_lookup_key(layer, table_name) in table_allowlist
        ]
    if exclude_keys:
        tables = [
            (table_name, layer)
            for table_name, layer in tables
            if baseline_lookup_key(layer, table_name) not in exclude_keys
        ]
    if not tables:
        return [
            ValidationResult(
                table=dag_name,
                baseline_count=0,
                emr_count=0,
                count_delta_pct=0.0,
                schema_match=False,
                schema_issues=[message],
                sample_match=False,
                sample_diff_rows=[],
                status="FAIL",
                message=message,
            )
        ]
    return [
        ValidationResult(
            table=format_table_label(layer, table_name),
            baseline_count=0,
            emr_count=0,
            count_delta_pct=0.0,
            schema_match=False,
            schema_issues=[message],
            sample_match=False,
            sample_diff_rows=[],
            status="FAIL",
            message=message,
        )
        for table_name, layer in tables
    ]


def _run_phase2(
    args: argparse.Namespace,
    load_start: str,
    load_end: str,
    *,
    git_ref: str | None,
    repo_root: Path,
    table_filter: str | None = None,
    table_allowlist: Optional[Set[TableScopeKey]] = None,
    layer_filter: str | None = None,
) -> tuple[list, str]:
    cluster_id = resolve_databricks_cluster(args.cluster, args.profile)
    db_api = DatabricksAPI(args.profile, cluster_id, timeout_sec=args.timeout)
    phase2 = DatabricksBaseline(
        db_api=db_api,
        dag_name=args.dag,
        domain=args.domain,
        load_start_date=load_start,
        load_end_date=load_end,
        git_ref=git_ref,
        skip_sample=args.skip_sample,
        skip_profile=args.skip_profile,
        table_filter=table_filter,
        layer_filter=layer_filter,
        table_allowlist=table_allowlist,
        repo_root=repo_root,
    )
    if not phase2.run():
        scope = (
            f"{layer_filter}/{table_filter}"
            if layer_filter and table_filter
            else table_filter or args.dag
        )
        raise RuntimeError(f"Databricks baseline capture failed for {scope}")
    return phase2.baselines, cluster_id


def _run_phase4(
    args: argparse.Namespace,
    baselines: list,
    load_start: str,
    load_end: str,
    *,
    git_ref: str | None,
    baseline_git_ref: str,
    repo_root: Path,
    quiet: bool,
    fail_fast: bool,
    table_allowlist: Optional[Set[TableScopeKey]] = None,
) -> tuple[bool, str, list]:
    ensure_aws_credentials(args.emr_env)
    emr_cluster_id = resolve_validation_emr_cluster(
        args.emr_cluster,
        emr_env=args.emr_env,
        new_session=args.new_emr_session,
        allow_create=not args.no_create_emr,
    )
    phase4 = EMRValidation(
        emr_cluster_id=emr_cluster_id,
        dag_name=args.dag,
        domain=args.domain,
        baselines=baselines,
        emr_env=args.emr_env,
        staging_uri=args.staging_uri,
        skip_sample=args.skip_sample,
        skip_profile=args.skip_profile,
        table_filter=args.table,
        git_ref=git_ref,
        baseline_git_ref=baseline_git_ref,
        repo_root=repo_root,
        load_start_date=load_start,
        load_end_date=load_end,
        allow_create_emr=not args.no_create_emr,
        quiet=quiet,
        fail_fast=fail_fast,
        table_allowlist=table_allowlist,
    )
    success = phase4.run()
    return success, emr_cluster_id, phase4.results


def _submit_config_from_args(
    args: argparse.Namespace,
    *,
    load_start: str,
    load_end: str,
    baseline_git_ref: str,
    table_allowlist: Optional[Set[TableScopeKey]],
    skipped_tables: list[str],
    repo_root: Path,
) -> SubmitConfig:
    session = load_session()
    return SubmitConfig(
        domain=args.domain,
        dag=args.dag,
        load_start_date=load_start,
        load_end_date=load_end,
        baseline_git_ref=baseline_git_ref,
        databricks_profile=args.profile,
        databricks_cluster_id=args.cluster or "",
        emr_cluster_id=(
            args.emr_cluster
            or ("" if args.new_emr_session else str(session.get("emr_cluster_id") or ""))
        ),
        emr_env=args.emr_env,
        staging_uri=args.staging_uri,
        skip_sample=args.skip_sample,
        skip_profile=args.skip_profile,
        timeout_sec=args.timeout,
        table_filter=args.table,
        table_allowlist=table_allowlist,
        repo_root=repo_root,
        max_parallel=args.max_parallel,
        allow_create_emr=not args.no_create_emr,
        new_emr_session=args.new_emr_session,
        run_id=args.run_id,
        skipped_tables=skipped_tables,
    )


def _run_async_submit(
    args: argparse.Namespace,
    *,
    load_start: str,
    load_end: str,
    baseline_git_ref: str,
    table_allowlist: Optional[Set[TableScopeKey]],
    skipped_tables: list[str],
    repo_root: Path,
) -> str:
    config = _submit_config_from_args(
        args,
        load_start=load_start,
        load_end=load_end,
        baseline_git_ref=baseline_git_ref,
        table_allowlist=table_allowlist,
        skipped_tables=skipped_tables,
        repo_root=repo_root,
    )
    manifest = run_submit(config)
    print(f"run_id={manifest.run_id}")
    print(f"manifest={manifest.manifest_s3_uri}")
    print(f"jobs={len(manifest.jobs)}")
    return manifest.run_id


def _run_async_watch(args: argparse.Namespace) -> int:
    run_id = args.run_id or str(load_session().get("active_run_id") or "")
    if not run_id:
        logger.error("--run-id is required for watch phase")
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
        domain_filter=args.domain if args.dag else None,
        dag_filter=args.dag,
    )
    manifest, dag_results = run_watch(config)

    syntax_ok = not watch_has_syntax_failures(dag_results)

    if args.dag and f"{args.domain}/{args.dag}" in dag_results:
        results = dag_results[f"{args.domain}/{args.dag}"]
        report_path = SKILL_DIR / "reports" / args.domain / f"{args.dag}_{date.today()}.md"
        skipped = manifest.skipped_tables.get(f"{args.domain}/{args.dag}", [])
        print_compare_summary(args.dag, results, report_path, skipped_tables=skipped)
    elif dag_results:
        print_batch_gate_summary(dag_results)

    return 0 if syntax_ok else 1


def _run_async_compare(
    args: argparse.Namespace,
    *,
    load_start: str,
    load_end: str,
    baseline_git_ref: str,
    table_allowlist: Optional[Set[TableScopeKey]],
    skipped_tables: list[str],
    repo_root: Path,
) -> int:
    if table_allowlist is not None and not table_allowlist:
        return _finalize_compare_run(
            args,
            [],
            skipped_tables=skipped_tables,
            db_cluster_id=args.cluster or "",
            emr_cluster_id=args.emr_cluster or "",
            load_start=load_start,
            load_end=load_end,
        )

    run_id = _run_async_submit(
        args,
        load_start=load_start,
        load_end=load_end,
        baseline_git_ref=baseline_git_ref,
        table_allowlist=table_allowlist,
        skipped_tables=skipped_tables,
        repo_root=repo_root,
    )
    args.run_id = run_id

    if args.detach and not args.no_detach:
        pid, log_path = spawn_detached_watch(
            run_id,
            domain=args.domain,
            dag=args.dag,
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

    return _run_async_watch(args)


def _finalize_compare_run(
    args: argparse.Namespace,
    results: list,
    *,
    skipped_tables: list[str],
    db_cluster_id: str,
    emr_cluster_id: str,
    load_start: str,
    load_end: str,
    success: bool = True,
) -> int:
    """Write mandatory report/summary and print terminal outcome."""
    fully_skipped = is_fully_skipped_dag(results, skipped_tables)
    report_path = write_report(
        args.domain,
        args.dag,
        results,
        databricks_cluster_id=db_cluster_id,
        emr_cluster_id=emr_cluster_id,
        load_start_date=load_start,
        load_end_date=load_end,
        skipped_tables=skipped_tables,
        fully_skipped=fully_skipped,
    )
    update_migration_summary(
        args.domain,
        args.dag,
        report_path,
        results,
        skipped_tables=skipped_tables,
        fully_skipped=fully_skipped,
    )
    if not fully_skipped:
        update_session_after_compare(
            domain=args.domain,
            dag_name=args.dag,
            report_path=report_path,
            results=results,
            load_start_date=load_start,
            load_end_date=load_end,
            databricks_cluster_id=db_cluster_id,
            emr_cluster_id=emr_cluster_id,
        )
    print_compare_summary(
        args.dag,
        results,
        report_path,
        skipped_tables=skipped_tables,
        fully_skipped=fully_skipped,
    )

    if not success:
        logger.error("Validation failed — see report")
        return 1
    return 0


def main() -> int:
    args = parse_args()
    args.skip_sample = not args.with_sample
    args.skip_profile = args.no_profile
    quiet = not args.verbose
    load_start = str(date.today() - timedelta(days=1))
    load_end = str(date.today())

    if args.phase == "watch":
        if not args.run_id and not load_session().get("active_run_id"):
            logger.error("watch requires --run-id or active_run_id in .session.yml")
            return 1
        return _run_async_watch(args)

    if args.phase in {"compare", "submit", "2", "4", "all"} and not args.cluster:
        logger.error(
            "--cluster is required (running Databricks all-purpose cluster id). "
            "Ask the user for a cluster id before running compare or submit."
        )
        return 1

    if args.phase in {"compare", "submit", "all"} and not args.dag:
        logger.error("--dag is required for phase %s", args.phase)
        return 1

    try:
        validate_cli_args(
            dag=args.dag or "",
            domain=args.domain,
            table=args.table,
            git_ref=args.git_ref,
        )
        validate_iso_date(load_start, "load_start_date")
        validate_iso_date(load_end, "load_end_date")
    except InputValidationError as exc:
        logger.error("%s", exc)
        return 1

    logger.info("=" * 70)
    logger.info("Databricks -> EMR Validation")
    logger.info("DAG: %s", args.dag)
    logger.info("Domain: %s", args.domain)
    logger.info("Phase: %s", args.phase)
    logger.info("Window: %s -> %s", load_start, load_end)
    logger.info("=" * 70)

    baselines: list = []
    db_cluster_id = args.cluster or ""
    emr_cluster_id = args.emr_cluster or str(load_session().get("emr_cluster_id") or "")
    results: list = []
    skipped_tables: list[str] = []

    run_phase2 = args.phase in {"compare", "2", "all"}
    run_phase4 = args.phase in {"compare", "4", "all"}

    baseline_git_ref = args.git_ref
    if run_phase2 and baseline_git_ref is None and args.phase in {"compare", "all"}:
        baseline_git_ref = "master"

    try:
        if baseline_git_ref is not None:
            validate_git_ref(baseline_git_ref)
    except InputValidationError as exc:
        logger.error("%s", exc)
        return 1

    compare_mode = args.phase in {"compare", "all"}
    repo_root = REPO_ROOT
    try:
        table_allowlist, skipped_tables = _resolve_table_allowlist(
            args,
            baseline_git_ref or "master",
            repo_root,
        )
    except (RuntimeError, FileNotFoundError) as exc:
        if compare_mode:
            logger.error("%s", exc)
            return _finalize_compare_run(
                args,
                _validation_results_for_workflow_error(
                    args.domain,
                    args.dag,
                    str(exc),
                    table_filter=args.table,
                    repo_root=repo_root,
                ),
                skipped_tables=[],
                db_cluster_id=db_cluster_id,
                emr_cluster_id=emr_cluster_id,
                load_start=load_start,
                load_end=load_end,
                success=False,
            )
        raise
    if table_allowlist is not None and not table_allowlist:
        logger.warning("No tables require translation — nothing to compare")
        if compare_mode:
            return _finalize_compare_run(
                args,
                [],
                skipped_tables=skipped_tables,
                db_cluster_id=db_cluster_id,
                emr_cluster_id=emr_cluster_id,
                load_start=load_start,
                load_end=load_end,
            )
        return 0

    use_async = args.phase in {"compare", "submit", "all"} and not args.sync
    if args.phase == "submit" and use_async:
        _run_async_submit(
            args,
            load_start=load_start,
            load_end=load_end,
            baseline_git_ref=baseline_git_ref or "master",
            table_allowlist=table_allowlist,
            skipped_tables=skipped_tables,
            repo_root=repo_root,
        )
        return 0

    if compare_mode and use_async and args.phase == "compare":
        return _run_async_compare(
            args,
            load_start=load_start,
            load_end=load_end,
            baseline_git_ref=baseline_git_ref or "master",
            table_allowlist=table_allowlist,
            skipped_tables=skipped_tables,
            repo_root=repo_root,
        )

    workflow_error: str | None = None
    baseline_failure_results: list[ValidationResult] = []
    success = True

    if run_phase2:
        try:
            if args.phase == "compare":
                needing = tables_needing_baseline(
                    args.domain,
                    args.dag,
                    load_start,
                    load_end,
                    args.table,
                    table_allowlist,
                    git_ref=baseline_git_ref or "master",
                    repo_root=repo_root,
                )
                if needing:
                    logger.info(
                        "Capturing Databricks baselines for %s table(s) from git ref %s",
                        len(needing),
                        baseline_git_ref,
                    )
                    for table_name, layer in needing:
                        logger.info(
                            "  Baseline pending: %s/%s (COUNT may take several minutes on large facts)",
                            layer,
                            table_name,
                        )
                        try:
                            _, db_cluster_id = _run_phase2(
                                args,
                                load_start,
                                load_end,
                                git_ref=baseline_git_ref,
                                repo_root=repo_root,
                                table_filter=table_name,
                                layer_filter=layer,
                                table_allowlist=table_allowlist,
                            )
                        except RuntimeError as exc:
                            message = str(exc)
                            logger.error(
                                "Baseline capture failed for %s/%s: %s",
                                layer,
                                table_name,
                                message,
                            )
                            baseline_failure_results.append(
                                _validation_result_for_baseline_failure(
                                    layer,
                                    table_name,
                                    message,
                                )
                            )
                else:
                    logger.info("All baselines present — skipping Databricks capture")
                baselines = load_baselines(
                    args.domain,
                    args.dag,
                    args.table,
                    table_allowlist=table_allowlist,
                )
            else:
                baselines, db_cluster_id = _run_phase2(
                    args,
                    load_start,
                    load_end,
                    git_ref=baseline_git_ref,
                    repo_root=repo_root,
                    table_filter=args.table,
                    table_allowlist=table_allowlist,
                )
        except FileNotFoundError as exc:
            if compare_mode:
                workflow_error = str(exc)
                logger.error("%s", exc)
            else:
                raise
        except RuntimeError as exc:
            if compare_mode and args.phase != "compare":
                workflow_error = str(exc)
                logger.error("%s", exc)
            elif not compare_mode:
                raise

    if run_phase4 and workflow_error is None:
        try:
            if not baselines:
                baselines = load_baselines(
                    args.domain,
                    args.dag,
                    args.table,
                    table_allowlist=table_allowlist,
                )

            failed_keys = _baseline_failure_keys(baseline_failure_results)
            emr_allowlist = _emr_table_allowlist(
                args.domain,
                args.dag,
                args.table,
                table_allowlist,
                failed_keys,
                repo_root,
            )

            emr_success = True
            if emr_allowlist is None or emr_allowlist:
                emr_success, emr_cluster_id, results = _run_phase4(
                    args,
                    baselines,
                    load_start,
                    load_end,
                    git_ref=None,
                    baseline_git_ref=baseline_git_ref or "master",
                    repo_root=repo_root,
                    quiet=quiet,
                    fail_fast=False if compare_mode else True,
                    table_allowlist=emr_allowlist,
                )
                success = emr_success
            else:
                results = []
        except RuntimeError as exc:
            if compare_mode:
                workflow_error = str(exc)
                logger.error("%s", exc)
            else:
                logger.error("%s", exc)
                return 1

    if baseline_failure_results:
        results = baseline_failure_results + results
        success = success and not baseline_failure_results

    if compare_mode:
        if workflow_error:
            results = results + _validation_results_for_workflow_error(
                args.domain,
                args.dag,
                workflow_error,
                table_filter=args.table,
                table_allowlist=table_allowlist,
                exclude_keys=_baseline_failure_keys(results),
                repo_root=repo_root,
            )
        compare_success = workflow_error is None and not syntax_failures(results)
        return _finalize_compare_run(
            args,
            results,
            skipped_tables=skipped_tables,
            db_cluster_id=db_cluster_id,
            emr_cluster_id=emr_cluster_id,
            load_start=load_start,
            load_end=load_end,
            success=compare_success,
        )

    if run_phase4 and not success:
        logger.error("Validation failed — see results")
        return 1

    logger.info("Validation complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
