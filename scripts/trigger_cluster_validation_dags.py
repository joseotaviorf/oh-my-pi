#!/usr/bin/env python3
"""Trigger and monitor cluster validation DAGs against a remote Airflow deployment."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import random
import secrets
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Literal, TextIO

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import requests  # noqa: E402

from scripts.airflow_rest_client import (  # noqa: E402
    AirflowApiError,
    AirflowAuth,
    AirflowRestClient,
)
from scripts.cluster_validation_conf_exceptions import (  # noqa: E402
    resolve_validation_conf_for_dag,
)
from scripts.cluster_validation_dag_discovery import (  # noqa: E402
    ValidationDag,
    discover_validation_dags,
    filter_validation_dags,
    group_by_line,
)
from scripts.cluster_validation_reference import (  # noqa: E402
    MIN_PROD_RUN_DURATION_SECONDS,
    LoadWindowSource,
    dag_run_duration_seconds,
    dag_run_id_from_payload,
    has_prod_success_within_days,
    load_window_from_prod_dag_run,
    parse_airflow_timestamp,
    select_reference_prod_run,
    validation_conf_with_reference,
)

DEFAULT_TRIGGER_LEDGER_PATH = (
    REPO_ROOT / "scripts" / "rightsizing_validation_trigger_ledger.jsonl"
)

TERMINAL_STATES = frozenset({"success", "failed", "upstream_failed"})
FAILURE_STATES = frozenset({"failed", "upstream_failed"})
ACTIVE_DAG_RUN_STATES = frozenset({"queued", "running", "deferred"})
CONF_MATCH_KEYS = ("run_type", "load_start_date", "load_end_date")
DATABRICKS_MAX_CLUSTER_NAME_LENGTH = 100
# prod_conf cluster_name: "{{ dag.dag_id }}_{{ run_id }}" (also used as Databricks job_cluster_key).
VALIDATION_RUN_ID_PREFIX = "val__"
VALIDATION_RUN_ID_SUFFIX_LEN = 4
VALIDATION_RUN_ID_MAX_LEN = (
    len(VALIDATION_RUN_ID_PREFIX) + 14 + 1 + VALIDATION_RUN_ID_SUFFIX_LEN
)
DATABRICKS_MAX_VALIDATION_DAG_ID_LENGTH = (
    DATABRICKS_MAX_CLUSTER_NAME_LENGTH - 1 - VALIDATION_RUN_ID_MAX_LEN
)
DEFAULT_VALIDATION_COOLDOWN_HOURS = 2.0
VALIDATION_TIMEOUT_PROD_WALL_FACTOR = 2.0
TRANSIENT_HTTP_STATUS_CODES = frozenset({408, 429, 502, 503, 504})
# Backward-compatible aliases for unit tests and dry-run helpers.
_dag_run_id_from_payload = dag_run_id_from_payload
_dag_run_duration_seconds = dag_run_duration_seconds
_load_window_from_prod_dag_run = load_window_from_prod_dag_run
_select_reference_prod_run = select_reference_prod_run
_has_prod_success_within_days = has_prod_success_within_days


@dataclass
class RunOutcome:
    dag: ValidationDag
    dag_run_id: str | None
    final_state: str
    duration_seconds: float | None = None
    error_message: str | None = None


@dataclass(frozen=True)
class RunAction:
    action: Literal["monitor", "trigger", "skip"]
    dag_run_id: str | None
    reason: str


@dataclass
class DagExecutionPlan:
    dag: ValidationDag
    conf: dict[str, str] | None
    skip_reason: str | None = None
    prod_dag_run_id: str | None = None
    prod_duration_seconds: float | None = None
    window_source: LoadWindowSource | None = None
    validation_action: RunAction | None = None


@dataclass
class ProgressTracker:
    total: int
    successful: int = 0
    failed: int = 0
    skipped: int = 0
    active: int = 0
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    async def mark_triggered(self) -> None:
        async with self.lock:
            self.active += 1

    async def mark_outcome(
        self, final_state: str, *, release_active_slot: bool = True
    ) -> None:
        async with self.lock:
            if final_state == "success":
                self.successful += 1
            elif final_state == "skipped":
                self.skipped += 1
            else:
                self.failed += 1
            if release_active_slot and self.active > 0:
                self.active -= 1

    async def snapshot(self) -> tuple[int, int, int, int, int]:
        async with self.lock:
            return self.successful, self.failed, self.skipped, self.total, self.active


class EventPrinter:
    def __init__(
        self, stdout: TextIO = sys.stdout, stderr: TextIO = sys.stderr
    ) -> None:
        self.stdout = stdout
        self.stderr = stderr
        self._lock = asyncio.Lock()

    async def emit(self, message: str, *, stream: TextIO | None = None) -> None:
        target = stream or self.stdout
        async with self._lock:
            print(message, file=target, flush=True)

    async def emit_event(
        self,
        label: str,
        dag_id: str,
        detail: str = "",
        *,
        progress: ProgressTracker | None = None,
        stream: TextIO | None = None,
    ) -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        suffix = ""
        if progress is not None:
            successful, failed, skipped, total, active = await progress.snapshot()
            suffix = f"  ({successful}/{failed}/{skipped}/{total}"
            if active:
                suffix += f", {active} active"
            suffix += ")"
        detail_part = f"  {detail}" if detail else ""
        await self.emit(
            f"[{timestamp}] {label:<9} {dag_id}{detail_part}{suffix}",
            stream=stream,
        )


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=os.environ.get("AIRFLOW_API_URL"))
    parser.add_argument("--token", default=os.environ.get("AIRFLOW_AUTH_TOKEN"))
    parser.add_argument("--username", default=os.environ.get("AIRFLOW_USERNAME"))
    parser.add_argument("--password", default=os.environ.get("AIRFLOW_PASSWORD"))
    parser.add_argument("--lines", help="Comma-separated dags/<line> names to include")
    parser.add_argument("--exclude-lines", help="Comma-separated lines to exclude")
    parser.add_argument("--dags", help="Comma-separated short dag names to include")
    parser.add_argument(
        "--exclude-dags", help="Comma-separated short dag names to exclude"
    )
    parser.add_argument(
        "--dag-ids", help="Comma-separated full Airflow dag ids to include"
    )
    parser.add_argument("--load-start-date")
    parser.add_argument("--load-end-date")
    parser.add_argument(
        "--allow-default-dates",
        action="store_true",
        help="Use a wide default date window when load dates are omitted",
    )
    parser.add_argument("--max-parallel", type=int, default=15)
    parser.add_argument(
        "--poll-interval",
        type=float,
        default=30.0,
        help="Base seconds between status polls (exponential backoff applies)",
    )
    parser.add_argument(
        "--poll-max-interval",
        type=float,
        default=300.0,
        help="Cap on poll backoff delay in seconds (default 300)",
    )
    parser.add_argument(
        "--poll-jitter",
        type=float,
        default=0.25,
        help="Fractional jitter on poll delays; 0 disables (default 0.25)",
    )
    parser.add_argument(
        "--max-runs",
        type=int,
        default=1,
        help=(
            "Deprecated: skip uses the latest validation run state only. "
            "Kept for CLI compatibility (default 1)"
        ),
    )
    parser.add_argument(
        "--force-retrigger",
        action="store_true",
        help=(
            "Trigger again after prior success; still respects "
            "--validation-cooldown-hours and active-run resume"
        ),
    )
    parser.add_argument(
        "--validation-cooldown-hours",
        type=float,
        default=DEFAULT_VALIDATION_COOLDOWN_HOURS,
        help=(
            "Skip when a terminal validation run finished within this many hours "
            f"(default {DEFAULT_VALIDATION_COOLDOWN_HOURS:g}; applies even with "
            "--force-retrigger; use 0 to disable)"
        ),
    )
    parser.add_argument(
        "--dag-runs-lookback",
        type=int,
        default=25,
        help="Recent dag runs to inspect per DAG for resume/skip (default 25)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=7200,
        help=(
            "Floor monitor timeout in seconds (default 7200); raised per-DAG to "
            "2× the reference prod run duration when known"
        ),
    )
    parser.add_argument("--log-tail-lines", type=int, default=80)
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument(
        "--list", action="store_true", help="List selected DAGs and exit"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Show what would be triggered"
    )
    parser.add_argument(
        "--skip-missing",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Skip DAGs not found in Airflow (default: true)",
    )
    parser.add_argument(
        "--require-all-deployed",
        action="store_true",
        help="Fail if any selected DAG is missing from Airflow",
    )
    parser.add_argument(
        "--dags-root",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "dags",
    )
    parser.add_argument(
        "--from-prod-run",
        action="store_true",
        help="Derive per-DAG load window from fastest successful prod run",
    )
    parser.add_argument(
        "--prod-run-lookback-days",
        type=int,
        default=14,
        help="Days to search for fastest successful prod run (default 14)",
    )
    parser.add_argument(
        "--prod-run-recency-days",
        type=int,
        default=7,
        help="Skip when prod DAG has no success in this many days (default 7)",
    )
    parser.add_argument(
        "--no-prod-run-recency-filter",
        action="store_true",
        help="Do not skip prod DAGs with no recent successful run",
    )
    parser.add_argument(
        "--prod-run-lookback-limit",
        type=int,
        default=100,
        help="Max successful prod dag runs to fetch per DAG (default 100)",
    )
    args = parser.parse_args(argv)
    _validate_args(args)
    return args


def _validate_args(args: argparse.Namespace) -> None:
    if args.from_prod_run and (args.load_start_date or args.load_end_date):
        raise SystemExit(
            "Cannot combine --from-prod-run with --load-start-date / --load-end-date."
        )
    if args.from_prod_run and args.allow_default_dates:
        raise SystemExit("Cannot combine --from-prod-run with --allow-default-dates.")


def _needs_explicit_load_dates(args: argparse.Namespace) -> bool:
    if args.list and not args.dry_run:
        return False
    if args.from_prod_run:
        return False
    return True


def _resolve_trigger_conf(args: argparse.Namespace) -> dict[str, str]:
    start = args.load_start_date
    end = args.load_end_date
    if not start or not end:
        if not _needs_explicit_load_dates(args):
            raise SystemExit("Internal error: load dates required but not expected.")
        if not args.allow_default_dates:
            raise SystemExit(
                "Missing --load-start-date / --load-end-date. "
                "Pass both or use --allow-default-dates."
            )
        start = start or "2019-01-01"
        end = end or "2026-12-31"
        print(
            f"WARNING: using default load window {start} .. {end}",
            file=sys.stderr,
        )
    return {
        "run_type": "test_run",
        "load_start_date": start,
        "load_end_date": end,
    }


def _build_client(args: argparse.Namespace) -> AirflowRestClient:
    if not args.url:
        raise SystemExit("Missing Airflow URL. Set AIRFLOW_API_URL or pass --url.")
    if not args.token and not (args.username and args.password):
        raise SystemExit(
            "Missing auth. Set AIRFLOW_AUTH_TOKEN or AIRFLOW_USERNAME/PASSWORD."
        )
    auth = AirflowAuth(
        token=args.token,
        username=args.username,
        password=args.password,
    )
    return AirflowRestClient(args.url, auth)


def _print_dag_list(
    dags: list[ValidationDag], *, dry_run: bool = False, list_mode: bool = False
) -> None:
    prefix = "Would trigger" if dry_run else "Selected"
    if list_mode and not dry_run:
        prefix = "Selected"
    grouped = group_by_line(dags)
    print(f"{prefix} {len(dags)} validation DAG(s):\n")
    for line in sorted(grouped):
        print(f"## {line} ({len(grouped[line])})")
        for item in grouped[line]:
            print(f"  {item.dag_id}  ({item.cluster_path_display})")


def _resolve_deployed_dag_ids(client: AirflowRestClient) -> set[str]:
    deployed = client.list_dags_by_tag("cluster_validation")
    return {item["dag_id"] for item in deployed if item.get("dag_id")}


def _filter_deployed(
    dags: list[ValidationDag],
    deployed_ids: set[str],
    *,
    skip_missing: bool,
    require_all_deployed: bool,
) -> tuple[list[ValidationDag], list[ValidationDag]]:
    present: list[ValidationDag] = []
    missing: list[ValidationDag] = []
    for item in dags:
        if item.dag_id in deployed_ids:
            present.append(item)
        else:
            missing.append(item)

    if require_all_deployed and missing:
        names = ", ".join(item.dag_id for item in missing[:10])
        extra = f" (+{len(missing) - 10} more)" if len(missing) > 10 else ""
        raise SystemExit(f"Missing from Airflow: {names}{extra}")

    if skip_missing and missing:
        for item in missing:
            print(f"WARNING: skipping missing DAG {item.dag_id}", file=sys.stderr)

    return present if skip_missing else dags, missing


def _format_duration(seconds: float | None) -> str:
    if seconds is None:
        return ""
    minutes, secs = divmod(int(seconds), 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours}h{minutes}m{secs}s"
    if minutes:
        return f"{minutes}m{secs}s"
    return f"{secs}s"


def _effective_run_timeout(plan: DagExecutionPlan, base_timeout: int) -> int:
    """Per-DAG monitor timeout: a verdict needs room for ≥2x the reference prod wall."""
    if plan.prod_duration_seconds is None:
        return base_timeout
    return max(base_timeout, int(plan.prod_duration_seconds * VALIDATION_TIMEOUT_PROD_WALL_FACTOR))


def _tail_lines(text: str, max_lines: int) -> str:
    lines = text.splitlines()
    if len(lines) <= max_lines:
        return text
    return "\n".join(lines[-max_lines:])


def _compute_poll_delay(
    attempt: int,
    *,
    base_interval: float,
    max_interval: float,
    jitter_fraction: float,
) -> float:
    if base_interval <= 0:
        return 0.0
    delay = min(max_interval, base_interval * (2**attempt))
    if jitter_fraction > 0:
        delay *= random.uniform(1 - jitter_fraction, 1 + jitter_fraction)
    return delay


def _append_trigger_ledger(
    *,
    validation_dag_id: str,
    validation_dag_run_id: str,
    reference_prod_dag_id: str,
    reference_prod_dag_run_id: str | None,
    load_start_date: str,
    load_end_date: str,
    ledger_path: Path = DEFAULT_TRIGGER_LEDGER_PATH,
) -> None:
    record = {
        "validation_dag_id": validation_dag_id,
        "validation_dag_run_id": validation_dag_run_id,
        "reference_prod_dag_id": reference_prod_dag_id,
        "reference_prod_dag_run_id": reference_prod_dag_run_id,
        "load_start_date": load_start_date,
        "load_end_date": load_end_date,
        "triggered_at": datetime.now(timezone.utc).isoformat(),
    }
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    with ledger_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, sort_keys=True) + "\n")


def _resolve_prod_run_plan(
    client: AirflowRestClient,
    dag: ValidationDag,
    args: argparse.Namespace,
    *,
    now: datetime | None = None,
) -> DagExecutionPlan:
    reference_now = now or datetime.now(timezone.utc)
    try:
        runs = client.list_dag_runs(
            dag.original_dag_id,
            states=["success"],
            limit=args.prod_run_lookback_limit,
            order_by="-start_date",
        )
    except AirflowApiError as exc:
        if exc.status_code == 404:
            return DagExecutionPlan(
                dag=dag,
                conf=None,
                skip_reason=f"prod DAG not found: {dag.original_dag_id}",
            )
        raise

    if not args.no_prod_run_recency_filter and not _has_prod_success_within_days(
        runs,
        recency_days=args.prod_run_recency_days,
        now=reference_now,
    ):
        return DagExecutionPlan(
            dag=dag,
            conf=None,
            skip_reason=(
                f"prod not successfully executed in past {args.prod_run_recency_days} days"
            ),
        )

    reference_run = _select_reference_prod_run(
        runs,
        lookback_days=args.prod_run_lookback_days,
        now=reference_now,
    )
    if reference_run is None:
        min_minutes = MIN_PROD_RUN_DURATION_SECONDS // 60
        return DagExecutionPlan(
            dag=dag,
            conf=None,
            skip_reason=(
                f"no successful prod run of at least {min_minutes}m "
                f"in past {args.prod_run_lookback_days} days"
            ),
        )

    window = resolve_validation_conf_for_dag(dag.original_dag_id, reference_run)
    if window is None:
        return DagExecutionPlan(
            dag=dag,
            conf=None,
            skip_reason="could not resolve load window from prod run",
        )

    conf, source = window
    prod_dag_run_id = _dag_run_id_from_payload(reference_run)
    prod_duration_seconds = _dag_run_duration_seconds(reference_run)
    enriched_conf = validation_conf_with_reference(
        conf,
        reference_prod_dag_run_id=prod_dag_run_id,
        reference_prod_duration_seconds=prod_duration_seconds,
        window_source=source,
    )
    return DagExecutionPlan(
        dag=dag,
        conf=enriched_conf,
        prod_dag_run_id=prod_dag_run_id,
        prod_duration_seconds=prod_duration_seconds,
        window_source=source,
    )


def _attach_validation_action(
    client: AirflowRestClient,
    plan: DagExecutionPlan,
    args: argparse.Namespace,
) -> DagExecutionPlan:
    if plan.conf is None:
        return plan
    plan.validation_action = _resolve_run_action(
        client,
        plan.dag,
        force_retrigger=args.force_retrigger,
        dag_runs_lookback=args.dag_runs_lookback,
        validation_cooldown_hours=args.validation_cooldown_hours,
    )
    return plan


def _build_validation_dag_run_id(
    *, now: datetime | None = None
) -> tuple[str, str]:
    """Return a short Airflow dag_run_id and matching logical_date for validation triggers."""
    reference = now or datetime.now(timezone.utc)
    timestamp = reference.strftime("%Y%m%d%H%M%S")
    suffix = secrets.token_hex(2)
    dag_run_id = f"{VALIDATION_RUN_ID_PREFIX}{timestamp}_{suffix}"
    return dag_run_id, reference.isoformat()


def _dag_id_exceeds_databricks_limit(dag_id: str) -> bool:
    return (
        len(dag_id) + 1 + VALIDATION_RUN_ID_MAX_LEN
        > DATABRICKS_MAX_CLUSTER_NAME_LENGTH
    )


def _dag_id_too_long_skip_reason(dag_id: str) -> str:
    return (
        f"dag_id too long for Databricks cluster_name "
        f"(len={len(dag_id)}, limit {DATABRICKS_MAX_VALIDATION_DAG_ID_LENGTH} "
        f"for dag_id)"
    )


def _skip_plan_too_long_dag_id(dag: ValidationDag) -> DagExecutionPlan:
    return DagExecutionPlan(
        dag=dag,
        conf=None,
        skip_reason=_dag_id_too_long_skip_reason(dag.dag_id),
    )


def _build_execution_plans(
    client: AirflowRestClient,
    dags: list[ValidationDag],
    args: argparse.Namespace,
) -> list[DagExecutionPlan]:
    plans: list[DagExecutionPlan] = []
    for dag in dags:
        if _dag_id_exceeds_databricks_limit(dag.dag_id):
            plans.append(_skip_plan_too_long_dag_id(dag))
            continue
        if args.from_prod_run:
            plan = _resolve_prod_run_plan(client, dag, args)
        else:
            plan = DagExecutionPlan(dag=dag, conf=_resolve_trigger_conf(args))
        plans.append(_attach_validation_action(client, plan, args))
    return plans


def _validation_action_label(plan: DagExecutionPlan) -> str:
    if plan.skip_reason:
        return f"SKIP {plan.skip_reason}"
    if plan.validation_action is None:
        return "-"
    action = plan.validation_action
    if action.action == "trigger":
        return "TRIGGER"
    if action.action == "monitor":
        return f"RESUME ({action.reason})"
    return f"SKIP ({action.reason})"


def _print_dry_run_table(plans: list[DagExecutionPlan]) -> None:
    trigger_count = sum(
        1
        for plan in plans
        if plan.conf is not None
        and (
            plan.validation_action is None or plan.validation_action.action == "trigger"
        )
    )
    print(
        f"Would process {len(plans)} validation DAG(s) ({trigger_count} to trigger):\n"
    )

    headers = (
        "LINE",
        "VALIDATION_DAG",
        "PROD_RUN_ID",
        "DURATION",
        "LOAD_START",
        "LOAD_END",
        "SRC",
        "ACTION",
    )
    widths = (12, 44, 36, 8, 12, 12, 34, 32)
    header_line = "  ".join(
        header.ljust(width) for header, width in zip(headers, widths, strict=True)
    )
    print(header_line)
    print("-" * len(header_line))

    for plan in sorted(plans, key=lambda item: (item.dag.line, item.dag.dag_name)):
        conf = plan.conf or {}
        prod_run_id = plan.prod_dag_run_id or "-"
        duration = _format_duration(plan.prod_duration_seconds) or "-"
        load_start = conf.get("load_start_date", "-")
        load_end = conf.get("load_end_date", "-")
        source = plan.window_source or "-"
        action = _validation_action_label(plan)
        row = (
            plan.dag.line[: widths[0]],
            plan.dag.dag_id[: widths[1]],
            prod_run_id[: widths[2]],
            duration[: widths[3]],
            str(load_start)[: widths[4]],
            str(load_end)[: widths[5]],
            source[: widths[6]],
            action[: widths[7]],
        )
        print(
            "  ".join(
                value.ljust(width) for value, width in zip(row, widths, strict=True)
            )
        )


def _conf_matches(run_conf: Any, expected_conf: dict[str, str]) -> bool:
    if not isinstance(run_conf, dict):
        return False
    for key in CONF_MATCH_KEYS:
        if str(run_conf.get(key)) != str(expected_conf.get(key)):
            return False
    return True


def _dag_run_start_sort_key(run: dict[str, Any]) -> str:
    return str(run.get("start_date") or "")


def _latest_terminal_run(runs: list[dict[str, Any]]) -> dict[str, Any] | None:
    terminal_runs = [run for run in runs if run.get("state") in TERMINAL_STATES]
    if not terminal_runs:
        return None
    return max(terminal_runs, key=_dag_run_start_sort_key)


def _run_finished_within_hours(
    run: dict[str, Any],
    *,
    hours: float,
    now: datetime,
) -> bool:
    if hours <= 0:
        return False
    end = parse_airflow_timestamp(run.get("end_date"))
    start = parse_airflow_timestamp(run.get("start_date"))
    reference = end or start
    if reference is None:
        return False
    return reference >= now - timedelta(hours=hours)


def _resolve_run_action(
    client: AirflowRestClient,
    dag: ValidationDag,
    *,
    force_retrigger: bool,
    dag_runs_lookback: int,
    validation_cooldown_hours: float = DEFAULT_VALIDATION_COOLDOWN_HOURS,
    now: datetime | None = None,
) -> RunAction:
    if _dag_id_exceeds_databricks_limit(dag.dag_id):
        return RunAction(
            action="skip",
            dag_run_id=None,
            reason=_dag_id_too_long_skip_reason(dag.dag_id),
        )

    reference_now = now or datetime.now(timezone.utc)
    runs = client.list_dag_runs(
        dag.dag_id,
        limit=dag_runs_lookback,
        order_by="-start_date",
    )

    active_runs = [
        run for run in runs if run.get("state") in ACTIVE_DAG_RUN_STATES
    ]
    if active_runs:
        latest = max(active_runs, key=_dag_run_start_sort_key)
        run_id = _dag_run_id_from_payload(latest)
        return RunAction(
            action="monitor",
            dag_run_id=run_id,
            reason=f"active run ({latest.get('state')})",
        )

    latest_terminal = _latest_terminal_run(runs)
    if latest_terminal is not None and _run_finished_within_hours(
        latest_terminal,
        hours=validation_cooldown_hours,
        now=reference_now,
    ):
        run_id = _dag_run_id_from_payload(latest_terminal)
        state = str(latest_terminal.get("state") or "terminal")
        return RunAction(
            action="skip",
            dag_run_id=run_id,
            reason=(
                f"recent {state} run within {validation_cooldown_hours:g}h "
                f"({run_id})"
            ),
        )

    if force_retrigger:
        return RunAction(action="trigger", dag_run_id=None, reason="force-retrigger")

    if latest_terminal is not None and latest_terminal.get("state") == "success":
        run_id = _dag_run_id_from_payload(latest_terminal)
        return RunAction(
            action="skip",
            dag_run_id=run_id,
            reason=f"already validated (last run success: {run_id})",
        )

    return RunAction(
        action="trigger",
        dag_run_id=None,
        reason="last run not successful",
    )


def _is_transient_api_error(exc: BaseException) -> bool:
    if isinstance(exc, requests.RequestException):
        return True
    if isinstance(exc, AirflowApiError):
        return exc.status_code in TRANSIENT_HTTP_STATUS_CODES
    return False


def _api_retry_base_interval(poll_interval: float) -> float:
    return poll_interval if poll_interval > 0 else 5.0


async def _call_airflow_with_retry(
    call: Callable[[], Any],
    *,
    semaphore: asyncio.Semaphore,
    printer: EventPrinter,
    dag_id: str,
    progress: ProgressTracker | None,
    started_at: float,
    timeout: int,
    poll_interval: float,
    poll_max_interval: float,
    poll_jitter: float,
) -> Any:
    api_attempt = 0
    while True:
        try:
            async with semaphore:
                return await asyncio.to_thread(call)
        except Exception as exc:
            if not _is_transient_api_error(exc):
                raise
            elapsed = time.monotonic() - started_at
            if elapsed >= timeout:
                raise
            delay = _compute_poll_delay(
                api_attempt,
                base_interval=_api_retry_base_interval(poll_interval),
                max_interval=poll_max_interval,
                jitter_fraction=poll_jitter,
            )
            await printer.emit_event(
                "RETRY",
                dag_id,
                str(exc),
                progress=progress,
            )
            if delay > 0:
                await asyncio.sleep(delay)
            api_attempt += 1


def _compute_initial_poll_delay(
    *,
    base_interval: float,
    max_interval: float,
    jitter_fraction: float,
) -> float:
    """Stagger first get_dag_run across [0, attempt-0 delay]."""
    upper = _compute_poll_delay(
        0,
        base_interval=base_interval,
        max_interval=max_interval,
        jitter_fraction=jitter_fraction,
    )
    if upper <= 0:
        return 0.0
    return random.uniform(0, upper)


async def _fetch_failure_logs(
    client: AirflowRestClient,
    semaphore: asyncio.Semaphore,
    printer: EventPrinter,
    progress: ProgressTracker,
    dag_id: str,
    dag_run_id: str,
    *,
    started_at: float,
    timeout: int,
    poll_interval: float,
    poll_max_interval: float,
    poll_jitter: float,
    log_tail_lines: int,
) -> list[tuple[str, str, str]]:
    task_instances = await _call_airflow_with_retry(
        lambda: client.list_task_instances(dag_id, dag_run_id),
        semaphore=semaphore,
        printer=printer,
        dag_id=dag_id,
        progress=progress,
        started_at=started_at,
        timeout=timeout,
        poll_interval=poll_interval,
        poll_max_interval=poll_max_interval,
        poll_jitter=poll_jitter,
    )

    failed_tasks = [
        task for task in task_instances if task.get("state") in FAILURE_STATES
    ]
    if not failed_tasks and task_instances:
        failed_tasks = [
            task
            for task in task_instances
            if task.get("state") not in {"success", "skipped", "removed", None}
            and task.get("state") not in {"queued", "scheduled", "running", "deferred"}
        ]

    logs: list[tuple[str, str, str]] = []
    for task in failed_tasks:
        task_id = task.get("task_id")
        if not task_id:
            continue
        try_number = task.get("try_number") or 1
        content = await _call_airflow_with_retry(
            lambda task_id=task_id, try_number=try_number: client.get_task_log(
                dag_id, dag_run_id, task_id, try_number
            ),
            semaphore=semaphore,
            printer=printer,
            dag_id=dag_id,
            progress=progress,
            started_at=started_at,
            timeout=timeout,
            poll_interval=poll_interval,
            poll_max_interval=poll_max_interval,
            poll_jitter=poll_jitter,
        )
        if not content:
            await asyncio.sleep(10)
            content = await _call_airflow_with_retry(
                lambda task_id=task_id, try_number=try_number: client.get_task_log(
                    dag_id, dag_run_id, task_id, try_number
                ),
                semaphore=semaphore,
                printer=printer,
                dag_id=dag_id,
                progress=progress,
                started_at=started_at,
                timeout=timeout,
                poll_interval=poll_interval,
                poll_max_interval=poll_max_interval,
                poll_jitter=poll_jitter,
            )
        logs.append((task_id, str(task.get("state", "")), content))
    return logs


async def _publish_failure_logs(
    client: AirflowRestClient,
    semaphore: asyncio.Semaphore,
    printer: EventPrinter,
    progress: ProgressTracker,
    dag: ValidationDag,
    dag_run_id: str,
    *,
    started_at: float,
    timeout: int,
    poll_interval: float,
    poll_max_interval: float,
    poll_jitter: float,
    log_tail_lines: int,
) -> None:
    logs = await _fetch_failure_logs(
        client,
        semaphore,
        printer,
        progress,
        dag.dag_id,
        dag_run_id,
        started_at=started_at,
        timeout=timeout,
        poll_interval=poll_interval,
        poll_max_interval=poll_max_interval,
        poll_jitter=poll_jitter,
        log_tail_lines=log_tail_lines,
    )
    await _print_failure_logs(printer, dag, dag_run_id, logs, log_tail_lines)


async def monitor_run(
    client: AirflowRestClient,
    semaphore: asyncio.Semaphore,
    printer: EventPrinter,
    progress: ProgressTracker,
    dag: ValidationDag,
    dag_run_id: str,
    *,
    poll_interval: float,
    poll_max_interval: float = 300.0,
    poll_jitter: float = 0.25,
    timeout: int,
    verbose: bool,
    log_tail_lines: int,
    fetch_failure_logs: bool = True,
) -> RunOutcome:
    started_at = time.monotonic()
    previous_state: str | None = "queued"
    previous_running_task: str | None = None
    poll_attempt = 0

    initial_delay = _compute_initial_poll_delay(
        base_interval=poll_interval,
        max_interval=poll_max_interval,
        jitter_fraction=poll_jitter,
    )
    if initial_delay > 0:
        await asyncio.sleep(initial_delay)

    while True:
        elapsed = time.monotonic() - started_at
        if elapsed >= timeout:
            await progress.mark_outcome("timeout")
            await printer.emit_event(
                "TIMEOUT",
                dag.dag_id,
                _format_duration(elapsed),
                progress=progress,
            )
            if fetch_failure_logs:
                await _publish_failure_logs(
                    client,
                    semaphore,
                    printer,
                    progress,
                    dag,
                    dag_run_id,
                    started_at=started_at,
                    timeout=timeout,
                    poll_interval=poll_interval,
                    poll_max_interval=poll_max_interval,
                    poll_jitter=poll_jitter,
                    log_tail_lines=log_tail_lines,
                )
            return RunOutcome(
                dag=dag,
                dag_run_id=dag_run_id,
                final_state="timeout",
                duration_seconds=elapsed,
                error_message="Timed out waiting for DAG run",
            )

        run_payload = await _call_airflow_with_retry(
            lambda: client.get_dag_run(dag.dag_id, dag_run_id),
            semaphore=semaphore,
            printer=printer,
            dag_id=dag.dag_id,
            progress=progress,
            started_at=started_at,
            timeout=timeout,
            poll_interval=poll_interval,
            poll_max_interval=poll_max_interval,
            poll_jitter=poll_jitter,
        )
        state = run_payload.get("state", "unknown")

        if state in TERMINAL_STATES:
            duration = time.monotonic() - started_at
            await progress.mark_outcome(state)
            if state != previous_state:
                detail = f"{previous_state} -> {state}"
                label = "RUNNING" if state == "running" else state.upper()
                await printer.emit_event(label, dag.dag_id, detail, progress=progress)
            if fetch_failure_logs and state in FAILURE_STATES:
                await _publish_failure_logs(
                    client,
                    semaphore,
                    printer,
                    progress,
                    dag,
                    dag_run_id,
                    started_at=started_at,
                    timeout=timeout,
                    poll_interval=poll_interval,
                    poll_max_interval=poll_max_interval,
                    poll_jitter=poll_jitter,
                    log_tail_lines=log_tail_lines,
                )
            return RunOutcome(
                dag=dag,
                dag_run_id=dag_run_id,
                final_state=state,
                duration_seconds=duration,
            )

        if state != previous_state:
            detail = f"{previous_state} -> {state}"
            label = "RUNNING" if state == "running" else state.upper()
            await printer.emit_event(label, dag.dag_id, detail, progress=progress)
            previous_state = state

        if verbose and state == "running":
            task_instances = await _call_airflow_with_retry(
                lambda: client.list_task_instances(dag.dag_id, dag_run_id),
                semaphore=semaphore,
                printer=printer,
                dag_id=dag.dag_id,
                progress=progress,
                started_at=started_at,
                timeout=timeout,
                poll_interval=poll_interval,
                poll_max_interval=poll_max_interval,
                poll_jitter=poll_jitter,
            )
            running = [
                task.get("task_id")
                for task in task_instances
                if task.get("state") == "running" and task.get("task_id")
            ]
            running_label = ", ".join(running[:3])
            if running_label and running_label != previous_running_task:
                await printer.emit_event(
                    "TASK",
                    dag.dag_id,
                    running_label,
                    progress=progress,
                )
                previous_running_task = running_label

        delay = _compute_poll_delay(
            poll_attempt,
            base_interval=poll_interval,
            max_interval=poll_max_interval,
            jitter_fraction=poll_jitter,
        )
        if delay > 0:
            await asyncio.sleep(delay)
        poll_attempt += 1


async def _print_failure_logs(
    printer: EventPrinter,
    dag: ValidationDag,
    dag_run_id: str,
    logs: list[tuple[str, str, str]],
    log_tail_lines: int,
) -> None:
    if not logs:
        await printer.emit(
            f"--- no failed task logs for {dag.dag_id} / {dag_run_id} ---",
            stream=printer.stderr,
        )
        return

    for task_id, state, content in logs:
        await printer.emit(
            f"--- logs: {dag.dag_id} / {dag_run_id} / {task_id} ({state}) ---",
            stream=printer.stderr,
        )
        await printer.emit(
            _tail_lines(content, log_tail_lines) or "(empty log)",
            stream=printer.stderr,
        )


async def trigger_and_monitor(
    client: AirflowRestClient,
    plans: list[DagExecutionPlan],
    *,
    max_parallel: int,
    max_runs: int,
    force_retrigger: bool,
    dag_runs_lookback: int,
    validation_cooldown_hours: float = DEFAULT_VALIDATION_COOLDOWN_HOURS,
    poll_interval: float,
    poll_max_interval: float = 300.0,
    poll_jitter: float = 0.25,
    timeout: int,
    verbose: bool,
    log_tail_lines: int,
) -> list[RunOutcome]:
    run_slots = asyncio.Semaphore(max_parallel)
    api_semaphore = asyncio.Semaphore(max_parallel)
    printer = EventPrinter()
    progress = ProgressTracker(total=len(plans))

    async def _monitor(dag: ValidationDag, dag_run_id: str, run_timeout: int) -> RunOutcome:
        try:
            return await monitor_run(
                client,
                api_semaphore,
                printer,
                progress,
                dag,
                dag_run_id,
                poll_interval=poll_interval,
                poll_max_interval=poll_max_interval,
                poll_jitter=poll_jitter,
                timeout=run_timeout,
                verbose=verbose,
                log_tail_lines=log_tail_lines,
                fetch_failure_logs=False,
            )
        except (AirflowApiError, requests.RequestException) as exc:
            await progress.mark_outcome("monitor_failed")
            await printer.emit_event(
                "ERROR",
                dag.dag_id,
                str(exc),
                progress=progress,
                stream=printer.stderr,
            )
            return RunOutcome(
                dag=dag,
                dag_run_id=dag_run_id,
                final_state="monitor_failed",
                error_message=str(exc),
            )

    async def _publish_outcome_failure_logs(outcome: RunOutcome) -> None:
        if not outcome.dag_run_id:
            return
        if outcome.final_state not in FAILURE_STATES and outcome.final_state != "timeout":
            return
        await _publish_failure_logs(
            client,
            api_semaphore,
            printer,
            progress,
            outcome.dag,
            outcome.dag_run_id,
            started_at=time.monotonic(),
            timeout=timeout,
            poll_interval=poll_interval,
            poll_max_interval=poll_max_interval,
            poll_jitter=poll_jitter,
            log_tail_lines=log_tail_lines,
        )

    async def process_one(plan: DagExecutionPlan) -> RunOutcome:
        dag = plan.dag
        if plan.conf is None or _dag_id_exceeds_databricks_limit(dag.dag_id):
            skip_reason = plan.skip_reason or (
                _dag_id_too_long_skip_reason(dag.dag_id)
                if _dag_id_exceeds_databricks_limit(dag.dag_id)
                else "skipped"
            )
            await progress.mark_outcome("skipped", release_active_slot=False)
            await printer.emit_event(
                "SKIPPED",
                dag.dag_id,
                skip_reason,
                progress=progress,
            )
            return RunOutcome(
                dag=dag,
                dag_run_id=None,
                final_state="skipped",
                error_message=skip_reason,
            )

        outcome: RunOutcome
        run_timeout = _effective_run_timeout(plan, timeout)
        async with run_slots:
            action = plan.validation_action
            if action is None:
                action = await asyncio.to_thread(
                    _resolve_run_action,
                    client,
                    dag,
                    force_retrigger=force_retrigger,
                    dag_runs_lookback=dag_runs_lookback,
                    validation_cooldown_hours=validation_cooldown_hours,
                )

            if action.action == "skip":
                await progress.mark_outcome("skipped", release_active_slot=False)
                await printer.emit_event(
                    "SKIPPED",
                    dag.dag_id,
                    action.reason,
                    progress=progress,
                )
                return RunOutcome(
                    dag=dag,
                    dag_run_id=action.dag_run_id,
                    final_state="skipped",
                )

            if action.action == "monitor":
                if not action.dag_run_id:
                    await progress.mark_outcome(
                        "monitor_failed", release_active_slot=False
                    )
                    return RunOutcome(
                        dag=dag,
                        dag_run_id=None,
                        final_state="monitor_failed",
                        error_message="active run missing dag_run_id",
                    )
                await progress.mark_triggered()
                await printer.emit_event(
                    "RESUME",
                    dag.dag_id,
                    f"run={action.dag_run_id}  {action.reason}",
                    progress=progress,
                )
                outcome = await _monitor(dag, action.dag_run_id, run_timeout)
            else:
                try:
                    unpaused = await asyncio.to_thread(
                        client.ensure_dag_unpaused, dag.dag_id
                    )
                    if unpaused:
                        await printer.emit_event(
                            "UNPAUSED",
                            dag.dag_id,
                            "was paused",
                            progress=progress,
                        )
                    custom_run_id, logical_date = _build_validation_dag_run_id()
                    payload = await asyncio.to_thread(
                        client.trigger_dag_run,
                        dag.dag_id,
                        plan.conf,
                        dag_run_id=custom_run_id,
                        logical_date=logical_date,
                    )
                    dag_run_id = payload["dag_run_id"]
                    if plan.conf is not None:
                        await asyncio.to_thread(
                            _append_trigger_ledger,
                            validation_dag_id=dag.dag_id,
                            validation_dag_run_id=dag_run_id,
                            reference_prod_dag_id=dag.original_dag_id,
                            reference_prod_dag_run_id=plan.prod_dag_run_id,
                            load_start_date=str(
                                plan.conf.get("load_start_date", "")
                            ),
                            load_end_date=str(plan.conf.get("load_end_date", "")),
                        )
                except (AirflowApiError, KeyError, requests.RequestException) as exc:
                    await progress.mark_outcome(
                        "trigger_failed", release_active_slot=False
                    )
                    await printer.emit_event(
                        "ERROR",
                        dag.dag_id,
                        str(exc),
                        progress=progress,
                        stream=printer.stderr,
                    )
                    return RunOutcome(
                        dag=dag,
                        dag_run_id=None,
                        final_state="trigger_failed",
                        error_message=str(exc),
                    )

                await progress.mark_triggered()
                await printer.emit_event(
                    "TRIGGERED",
                    dag.dag_id,
                    f"run={dag_run_id}",
                    progress=progress,
                )
                outcome = await _monitor(dag, dag_run_id, run_timeout)

        await _publish_outcome_failure_logs(outcome)
        return outcome

    results = await asyncio.gather(
        *(process_one(plan) for plan in plans),
        return_exceptions=True,
    )

    outcomes: list[RunOutcome] = []
    for plan, result in zip(plans, results, strict=True):
        if isinstance(result, Exception):
            outcomes.append(
                RunOutcome(
                    dag=plan.dag,
                    dag_run_id=None,
                    final_state="monitor_failed",
                    error_message=str(result),
                )
            )
        else:
            outcomes.append(result)
    return outcomes


def _print_summary(outcomes: list[RunOutcome]) -> None:
    print("\nSummary:")
    print(f"{'LINE':<24} {'DAG':<32} {'STATE':<16} {'DURATION':<10} RUN_ID")
    print("-" * 110)
    for outcome in sorted(
        outcomes, key=lambda item: (item.dag.line, item.dag.dag_name)
    ):
        duration = _format_duration(outcome.duration_seconds)
        run_id = outcome.dag_run_id or "-"
        print(
            f"{outcome.dag.line:<24} "
            f"{outcome.dag.dag_name:<32} "
            f"{outcome.final_state:<16} "
            f"{duration:<10} "
            f"{run_id}"
        )


def _exit_code(outcomes: list[RunOutcome]) -> int:
    if any(outcome.final_state not in {"success", "skipped"} for outcome in outcomes):
        return 1
    return 0


async def async_main(args: argparse.Namespace) -> int:
    selected = filter_validation_dags(
        discover_validation_dags(args.dags_root),
        lines=args.lines,
        exclude_lines=args.exclude_lines,
        dag_names=args.dags,
        exclude_dag_names=args.exclude_dags,
        dag_ids=args.dag_ids,
    )

    if not selected:
        print("No validation DAGs matched the filters.", file=sys.stderr)
        return 2

    if args.list and not args.dry_run:
        _print_dag_list(selected, list_mode=True)
        return 0

    client = _build_client(args)
    try:
        deployed_ids = await asyncio.to_thread(_resolve_deployed_dag_ids, client)
    except AirflowApiError as exc:
        print(f"Failed to list DAGs from Airflow: {exc}", file=sys.stderr)
        return 2

    to_trigger, _missing = _filter_deployed(
        selected,
        deployed_ids,
        skip_missing=args.skip_missing,
        require_all_deployed=args.require_all_deployed,
    )

    if not to_trigger:
        print("No deployed validation DAGs to trigger.", file=sys.stderr)
        return 2

    if args.max_runs != 1:
        print(
            "WARNING: --max-runs is deprecated; skip uses the latest validation "
            "run state only.",
            file=sys.stderr,
        )

    plans = await asyncio.to_thread(_build_execution_plans, client, to_trigger, args)

    if args.dry_run:
        _print_dry_run_table(plans)
        return 0

    outcomes = await trigger_and_monitor(
        client,
        plans,
        max_parallel=args.max_parallel,
        max_runs=args.max_runs,
        force_retrigger=args.force_retrigger,
        dag_runs_lookback=args.dag_runs_lookback,
        validation_cooldown_hours=args.validation_cooldown_hours,
        poll_interval=args.poll_interval,
        poll_max_interval=args.poll_max_interval,
        poll_jitter=args.poll_jitter,
        timeout=args.timeout,
        verbose=args.verbose,
        log_tail_lines=args.log_tail_lines,
    )
    _print_summary(outcomes)
    return _exit_code(outcomes)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    return asyncio.run(async_main(args))


if __name__ == "__main__":
    sys.exit(main())
