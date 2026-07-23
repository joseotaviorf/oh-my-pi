#!/usr/bin/env python3
"""Trigger and monitor EMR migration v2 validation DAGs via Airflow REST API.

Discovers migration_twin / migration_emr / migration_compare DAGs under
dags/platform/, triggers twin+emr pairs in controlled batches, and monitors
all three types until completion. Compare DAGs are auto-triggered by Airflow
Datasets and only monitored here.

Usage:
    uv run python .cursor/skills/emr-migration-v2/trigger_migration_dags.py --dry-run
    uv run python .cursor/skills/emr-migration-v2/trigger_migration_dags.py --max-parallel 32
"""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import os
import random
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any, TextIO

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import requests  # noqa: E402

from scripts.airflow_rest_client import (  # noqa: E402
    AirflowApiError,
    AirflowAuth,
    AirflowRestClient,
)

DAG_ID_PREFIX = ""
DAGS_PLATFORM_DIR = REPO_ROOT / "dags" / "platform"
TERMINAL_STATES = frozenset({"success", "failed", "upstream_failed"})
FAILURE_STATES = frozenset({"failed", "upstream_failed"})
TRANSIENT_HTTP_STATUS_CODES = frozenset({408, 429, 502, 503, 504})


class DagStatus(str, Enum):
    PENDING = "pending"
    TRIGGERED = "triggered"
    RUNNING = "running"
    SUCCESS = "success"
    FAILED = "failed"


@dataclass
class MigrationScope:
    scope_id: str
    twin_dag_id: str
    emr_dag_id: str
    compare_dag_id: str


@dataclass
class DagOutcome:
    dag_id: str
    dag_run_id: str | None = None
    status: DagStatus = DagStatus.PENDING
    duration_seconds: float | None = None
    error: str | None = None


@dataclass
class ScopeOutcome:
    scope: MigrationScope
    twin: DagOutcome = field(default=None)
    emr: DagOutcome = field(default=None)
    compare: DagOutcome = field(default=None)

    def __post_init__(self):
        if self.twin is None:
            self.twin = DagOutcome(dag_id=self.scope.twin_dag_id)
        if self.emr is None:
            self.emr = DagOutcome(dag_id=self.scope.emr_dag_id)
        if self.compare is None:
            self.compare = DagOutcome(dag_id=self.scope.compare_dag_id)


@dataclass
class ProgressTracker:
    total_scopes: int
    twin_success: int = 0
    twin_failed: int = 0
    emr_success: int = 0
    emr_failed: int = 0
    compare_success: int = 0
    compare_failed: int = 0
    active_pairs: int = 0
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    async def mark_twin(self, success: bool) -> None:
        async with self.lock:
            if success:
                self.twin_success += 1
            else:
                self.twin_failed += 1

    async def mark_emr(self, success: bool) -> None:
        async with self.lock:
            if success:
                self.emr_success += 1
            else:
                self.emr_failed += 1

    async def mark_compare(self, success: bool) -> None:
        async with self.lock:
            if success:
                self.compare_success += 1
            else:
                self.compare_failed += 1

    async def pair_started(self) -> None:
        async with self.lock:
            self.active_pairs += 1

    async def pair_finished(self) -> None:
        async with self.lock:
            self.active_pairs -= 1

    async def summary_line(self) -> str:
        async with self.lock:
            twin_done = self.twin_success + self.twin_failed
            emr_done = self.emr_success + self.emr_failed
            pairs_done = min(twin_done, emr_done)
            return (
                f"--- Progress: {pairs_done}/{self.total_scopes} pairs done"
                f" | twin: {self.twin_success}✓ {self.twin_failed}✗"
                f" | emr: {self.emr_success}✓ {self.emr_failed}✗"
                f" | compare: {self.compare_success}✓ {self.compare_failed}✗"
                f" | {self.active_pairs} active ---"
            )


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
        stream: TextIO | None = None,
    ) -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        short_id = dag_id.removeprefix(DAG_ID_PREFIX)
        detail_part = f"  {detail}" if detail else ""
        await self.emit(
            f"[{timestamp}] {label:<9} {short_id}{detail_part}",
            stream=stream,
        )


def discover_scopes(platform_dir: Path = DAGS_PLATFORM_DIR) -> list[MigrationScope]:
    twin_prefix = "migration_twin_"
    emr_prefix = "migration_emr_"
    compare_prefix = "migration_compare_"

    twin_dirs = {
        d.name.removeprefix(twin_prefix)
        for d in platform_dir.iterdir()
        if d.is_dir() and d.name.startswith(twin_prefix)
    }
    emr_dirs = {
        d.name.removeprefix(emr_prefix)
        for d in platform_dir.iterdir()
        if d.is_dir() and d.name.startswith(emr_prefix)
    }
    compare_dirs = {
        d.name.removeprefix(compare_prefix)
        for d in platform_dir.iterdir()
        if d.is_dir() and d.name.startswith(compare_prefix)
    }

    complete_scopes = twin_dirs & emr_dirs & compare_dirs
    scopes = []
    for scope_id in sorted(complete_scopes):
        scopes.append(
            MigrationScope(
                scope_id=scope_id,
                twin_dag_id=f"{DAG_ID_PREFIX}{twin_prefix}{scope_id}",
                emr_dag_id=f"{DAG_ID_PREFIX}{emr_prefix}{scope_id}",
                compare_dag_id=f"{DAG_ID_PREFIX}{compare_prefix}{scope_id}",
            )
        )

    orphan_twin = twin_dirs - complete_scopes
    orphan_emr = emr_dirs - complete_scopes
    orphan_compare = compare_dirs - complete_scopes
    if orphan_twin or orphan_emr or orphan_compare:
        print(
            f"WARNING: {len(orphan_twin)} twin, {len(orphan_emr)} emr, "
            f"{len(orphan_compare)} compare orphan scopes (missing counterparts)",
            file=sys.stderr,
        )

    return scopes


def filter_scopes(
    scopes: list[MigrationScope],
    *,
    include_domains: list[str] | None = None,
    exclude_domains: list[str] | None = None,
) -> list[MigrationScope]:
    filtered = scopes
    if include_domains:
        include_set = set(include_domains)
        filtered = [s for s in filtered if s.scope_id.split("__")[0] in include_set]
    if exclude_domains:
        exclude_set = set(exclude_domains)
        filtered = [s for s in filtered if s.scope_id.split("__")[0] not in exclude_set]
    return filtered


def _build_client(args: argparse.Namespace) -> AirflowRestClient:
    url = args.url or os.environ.get("AIRFLOW_API_URL")
    token = args.token or os.environ.get("AIRFLOW_AUTH_TOKEN")
    username = args.username or os.environ.get("AIRFLOW_USERNAME")
    password = args.password or os.environ.get("AIRFLOW_PASSWORD")
    if not url:
        raise SystemExit("Missing Airflow URL. Set AIRFLOW_API_URL or pass --url.")
    if not token and not (username and password):
        raise SystemExit(
            "Missing auth. Set AIRFLOW_AUTH_TOKEN or AIRFLOW_USERNAME/PASSWORD."
        )
    auth = AirflowAuth(token=token, username=username, password=password)
    return AirflowRestClient(url, auth)


def _format_duration(seconds: float | None) -> str:
    if seconds is None:
        return "-"
    minutes, secs = divmod(int(seconds), 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours}h{minutes}m{secs}s"
    if minutes:
        return f"{minutes}m{secs}s"
    return f"{secs}s"


def _compute_poll_delay(
    attempt: int,
    *,
    base_interval: float,
    max_interval: float,
    jitter_fraction: float = 0.25,
) -> float:
    if base_interval <= 0:
        return 0.0
    delay = min(max_interval, base_interval * (1.5**attempt))
    if jitter_fraction > 0:
        delay *= random.uniform(1 - jitter_fraction, 1 + jitter_fraction)
    return delay


def _is_transient_error(exc: BaseException) -> bool:
    if isinstance(exc, requests.RequestException):
        return True
    if isinstance(exc, AirflowApiError):
        return exc.status_code in TRANSIENT_HTTP_STATUS_CODES
    return False


def save_inventory(
    scopes: list[MigrationScope],
    max_parallel_pairs: int,
    output_dir: Path,
) -> Path:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = output_dir / f"trigger_inventory_{timestamp}.json"
    inventory = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_scopes": len(scopes),
        "max_parallel_pairs": max_parallel_pairs,
        "scopes": [
            {
                "scope_id": s.scope_id,
                "twin_dag_id": s.twin_dag_id,
                "emr_dag_id": s.emr_dag_id,
                "compare_dag_id": s.compare_dag_id,
            }
            for s in scopes
        ],
    }
    path.write_text(json.dumps(inventory, indent=2) + "\n")
    return path


def print_dry_run(scopes: list[MigrationScope], max_parallel_pairs: int) -> None:
    num_batches = math.ceil(len(scopes) / max_parallel_pairs)
    print("EMR Migration v2 — Trigger Plan")
    print("=" * 40)
    print(f"Scopes:       {len(scopes)}")
    print(f"Twin DAGs:    {len(scopes)}")
    print(f"EMR DAGs:     {len(scopes)}")
    print(f"Compare DAGs: {len(scopes)} (auto-triggered, monitored only)")
    print(f"Max parallel: {max_parallel_pairs * 2} DAGs ({max_parallel_pairs} pairs)")
    last_batch_size = len(scopes) - (num_batches - 1) * max_parallel_pairs
    if num_batches > 1:
        print(
            f"Batches:      {num_batches} "
            f"({num_batches - 1} × {max_parallel_pairs} pairs"
            f" + 1 × {last_batch_size} pairs)"
        )
    else:
        print(f"Batches:      1 ({last_batch_size} pairs)")
    print()

    for batch_idx in range(num_batches):
        start = batch_idx * max_parallel_pairs
        end = min(start + max_parallel_pairs, len(scopes))
        batch = scopes[start:end]
        print(f"Batch {batch_idx + 1} ({len(batch)} pairs):")
        for scope in batch:
            twin_short = scope.twin_dag_id.removeprefix(DAG_ID_PREFIX)
            emr_short = scope.emr_dag_id.removeprefix(DAG_ID_PREFIX)
            print(f"  {scope.scope_id:<50} {twin_short:<60} {emr_short}")
        print()


async def _api_call_with_retry(
    call,
    *,
    printer: EventPrinter,
    dag_id: str,
    max_retries: int = 5,
    base_interval: float = 10.0,
) -> Any:
    for attempt in range(max_retries + 1):
        try:
            return await asyncio.to_thread(call)
        except Exception as exc:
            if not _is_transient_error(exc) or attempt == max_retries:
                raise
            delay = _compute_poll_delay(
                attempt, base_interval=base_interval, max_interval=120.0
            )
            await printer.emit_event("RETRY", dag_id, str(exc))
            if delay > 0:
                await asyncio.sleep(delay)


async def trigger_and_poll(
    client: AirflowRestClient,
    dag_id: str,
    outcome: DagOutcome,
    *,
    printer: EventPrinter,
    poll_interval: float,
    timeout: int,
) -> DagOutcome:
    started_at = time.monotonic()

    try:
        unpaused = await _api_call_with_retry(
            lambda: client.ensure_dag_unpaused(dag_id),
            printer=printer,
            dag_id=dag_id,
        )
        if unpaused:
            await printer.emit_event("UNPAUSE", dag_id, "was paused")
    except Exception as exc:
        outcome.status = DagStatus.FAILED
        outcome.error = f"unpause failed: {exc}"
        await printer.emit_event("ERROR", dag_id, outcome.error, stream=printer.stderr)
        return outcome

    try:
        payload = await _api_call_with_retry(
            lambda: client.trigger_dag_run(dag_id, {}),
            printer=printer,
            dag_id=dag_id,
        )
        outcome.dag_run_id = payload.get("dag_run_id")
        outcome.status = DagStatus.TRIGGERED
        await printer.emit_event("TRIGGER", dag_id, f"run={outcome.dag_run_id}")
    except Exception as exc:
        outcome.status = DagStatus.FAILED
        outcome.error = f"trigger failed: {exc}"
        await printer.emit_event("ERROR", dag_id, outcome.error, stream=printer.stderr)
        return outcome

    previous_state: str | None = "queued"
    poll_attempt = 0
    await asyncio.sleep(random.uniform(5, 15))

    while True:
        elapsed = time.monotonic() - started_at
        if elapsed >= timeout:
            outcome.status = DagStatus.FAILED
            outcome.duration_seconds = elapsed
            outcome.error = "timeout"
            await printer.emit_event("TIMEOUT", dag_id, _format_duration(elapsed))
            return outcome

        try:
            run = await _api_call_with_retry(
                lambda: client.get_dag_run(dag_id, outcome.dag_run_id),
                printer=printer,
                dag_id=dag_id,
            )
        except Exception as exc:
            outcome.status = DagStatus.FAILED
            outcome.duration_seconds = time.monotonic() - started_at
            outcome.error = f"poll failed: {exc}"
            await printer.emit_event(
                "ERROR", dag_id, outcome.error, stream=printer.stderr
            )
            return outcome

        state = run.get("state", "unknown")

        if state != previous_state:
            if state == "running":
                outcome.status = DagStatus.RUNNING
                await printer.emit_event(
                    "RUNNING", dag_id, f"{previous_state} -> running"
                )
            elif state not in TERMINAL_STATES:
                await printer.emit_event(
                    state.upper(), dag_id, f"{previous_state} -> {state}"
                )
            previous_state = state

        if state in TERMINAL_STATES:
            outcome.duration_seconds = time.monotonic() - started_at
            if state == "success":
                outcome.status = DagStatus.SUCCESS
                await printer.emit_event(
                    "SUCCESS", dag_id, _format_duration(outcome.duration_seconds)
                )
            else:
                outcome.status = DagStatus.FAILED
                outcome.error = state
                await printer.emit_event(
                    "FAILED",
                    dag_id,
                    f"{state}  {_format_duration(outcome.duration_seconds)}",
                    stream=printer.stderr,
                )
            return outcome

        delay = _compute_poll_delay(
            min(poll_attempt, 6),
            base_interval=poll_interval,
            max_interval=120.0,
        )
        await asyncio.sleep(delay)
        poll_attempt += 1


async def process_pair(
    client: AirflowRestClient,
    scope_outcome: ScopeOutcome,
    *,
    semaphore: asyncio.Semaphore,
    printer: EventPrinter,
    tracker: ProgressTracker,
    poll_interval: float,
    timeout: int,
) -> ScopeOutcome:
    async with semaphore:
        await tracker.pair_started()
        twin_task = trigger_and_poll(
            client,
            scope_outcome.scope.twin_dag_id,
            scope_outcome.twin,
            printer=printer,
            poll_interval=poll_interval,
            timeout=timeout,
        )
        emr_task = trigger_and_poll(
            client,
            scope_outcome.scope.emr_dag_id,
            scope_outcome.emr,
            printer=printer,
            poll_interval=poll_interval,
            timeout=timeout,
        )
        await asyncio.gather(twin_task, emr_task)
        await tracker.mark_twin(scope_outcome.twin.status == DagStatus.SUCCESS)
        await tracker.mark_emr(scope_outcome.emr.status == DagStatus.SUCCESS)
        await tracker.pair_finished()

    return scope_outcome


async def monitor_compare_dags(
    client: AirflowRestClient,
    outcomes: list[ScopeOutcome],
    *,
    printer: EventPrinter,
    tracker: ProgressTracker,
    poll_interval: float = 60.0,
    timeout: float = 7200.0,
) -> None:
    pending = {o.scope.scope_id: o for o in outcomes}
    started_at = time.monotonic()
    seen_running: set[str] = set()

    while pending:
        elapsed = time.monotonic() - started_at
        if elapsed >= timeout:
            for scope_id, o in pending.items():
                o.compare.status = DagStatus.FAILED
                o.compare.error = "compare monitor timeout"
                await tracker.mark_compare(False)
                await printer.emit_event(
                    "TIMEOUT", o.scope.compare_dag_id, "compare monitor"
                )
            break

        for scope_id in list(pending.keys()):
            o = pending[scope_id]
            try:
                runs = await asyncio.to_thread(
                    client.list_dag_runs, o.scope.compare_dag_id, limit=1
                )
            except Exception:
                continue

            if not runs:
                continue

            run = runs[0]
            state = run.get("state", "unknown")
            run_id = run.get("dag_run_id", "")

            if state == "running" and scope_id not in seen_running:
                seen_running.add(scope_id)
                o.compare.dag_run_id = run_id
                o.compare.status = DagStatus.RUNNING
                await printer.emit_event(
                    "RUNNING", o.scope.compare_dag_id, "(auto-triggered)"
                )

            if state in TERMINAL_STATES:
                o.compare.dag_run_id = run_id
                if state == "success":
                    o.compare.status = DagStatus.SUCCESS
                    await tracker.mark_compare(True)
                    await printer.emit_event("SUCCESS", o.scope.compare_dag_id)
                else:
                    o.compare.status = DagStatus.FAILED
                    o.compare.error = state
                    await tracker.mark_compare(False)
                    await printer.emit_event(
                        "FAILED",
                        o.scope.compare_dag_id,
                        state,
                        stream=printer.stderr,
                    )
                del pending[scope_id]

        await asyncio.sleep(poll_interval)


async def progress_logger(
    tracker: ProgressTracker,
    printer: EventPrinter,
    *,
    interval: float = 60.0,
    stop_event: asyncio.Event,
) -> None:
    while not stop_event.is_set():
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=interval)
            break
        except asyncio.TimeoutError:
            pass
        line = await tracker.summary_line()
        await printer.emit(line)


def print_summary(outcomes: list[ScopeOutcome]) -> None:
    print("\n" + "=" * 100)
    print("Final Summary")
    print("=" * 100)
    print(f"{'SCOPE_ID':<50} {'TWIN':<10} {'EMR':<10} {'COMPARE':<10} {'DURATION':<10}")
    print("-" * 100)

    twin_ok = twin_fail = emr_ok = emr_fail = cmp_ok = cmp_fail = 0

    for o in sorted(outcomes, key=lambda x: x.scope.scope_id):
        twin_label = o.twin.status.value
        emr_label = o.emr.status.value
        compare_label = o.compare.status.value
        duration = _format_duration(
            max(
                o.twin.duration_seconds or 0,
                o.emr.duration_seconds or 0,
            )
            or None
        )
        print(
            f"{o.scope.scope_id:<50} "
            f"{twin_label:<10} {emr_label:<10} "
            f"{compare_label:<10} {duration:<10}"
        )
        if o.twin.status == DagStatus.SUCCESS:
            twin_ok += 1
        elif o.twin.status == DagStatus.FAILED:
            twin_fail += 1
        if o.emr.status == DagStatus.SUCCESS:
            emr_ok += 1
        elif o.emr.status == DagStatus.FAILED:
            emr_fail += 1
        if o.compare.status == DagStatus.SUCCESS:
            cmp_ok += 1
        elif o.compare.status == DagStatus.FAILED:
            cmp_fail += 1

    print("-" * 100)
    print(
        f"Total: {len(outcomes)} scopes"
        f" | Twin: {twin_ok}✓ {twin_fail}✗"
        f" | EMR: {emr_ok}✓ {emr_fail}✗"
        f" | Compare: {cmp_ok}✓ {cmp_fail}✗"
    )


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=None)
    parser.add_argument("--token", default=None)
    parser.add_argument("--username", default=None)
    parser.add_argument("--password", default=None)
    parser.add_argument(
        "--max-parallel",
        type=int,
        default=32,
        help="Max DAGs in flight (pairs = max-parallel / 2, default 32)",
    )
    parser.add_argument("--poll-interval", type=float, default=30.0)
    parser.add_argument("--timeout", type=int, default=3600)
    parser.add_argument(
        "--compare-timeout",
        type=int,
        default=7200,
        help="Timeout for compare DAG monitor in seconds (default 7200)",
    )
    parser.add_argument(
        "--scopes",
        help="Comma-separated domain names to include (e.g. agents,fintech)",
    )
    parser.add_argument(
        "--exclude-scopes",
        help="Comma-separated domain names to exclude",
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--save-inventory", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument(
        "--dags-root",
        type=Path,
        default=DAGS_PLATFORM_DIR,
    )
    return parser.parse_args(argv)


async def async_main(args: argparse.Namespace) -> int:
    scopes = discover_scopes(args.dags_root)
    if not scopes:
        print("No migration scopes found.", file=sys.stderr)
        return 2

    include = args.scopes.split(",") if args.scopes else None
    exclude = args.exclude_scopes.split(",") if args.exclude_scopes else None
    scopes = filter_scopes(scopes, include_domains=include, exclude_domains=exclude)
    if not scopes:
        print("No scopes matched the filters.", file=sys.stderr)
        return 2

    max_parallel_pairs = args.max_parallel // 2
    if max_parallel_pairs < 1:
        max_parallel_pairs = 1

    print(f"Discovered {len(scopes)} migration scopes.")

    skill_dir = Path(__file__).resolve().parent
    if args.dry_run or args.save_inventory:
        inv_path = save_inventory(scopes, max_parallel_pairs, skill_dir)
        print(f"Inventory saved to {inv_path}")

    if args.dry_run:
        print()
        print_dry_run(scopes, max_parallel_pairs)
        return 0

    client = _build_client(args)
    printer = EventPrinter()
    tracker = ProgressTracker(total_scopes=len(scopes))

    print("Unpausing compare DAGs so Datasets can trigger them...")
    unpaused_count = 0
    for scope in scopes:
        try:
            was_paused = await asyncio.to_thread(
                client.ensure_dag_unpaused, scope.compare_dag_id
            )
            if was_paused:
                unpaused_count += 1
        except Exception as exc:
            print(
                f"WARNING: failed to unpause {scope.compare_dag_id}: {exc}",
                file=sys.stderr,
            )
    print(f"Unpaused {unpaused_count} compare DAGs.")

    outcomes = [ScopeOutcome(scope=s) for s in scopes]
    semaphore = asyncio.Semaphore(max_parallel_pairs)

    stop_progress = asyncio.Event()
    progress_task = asyncio.create_task(
        progress_logger(tracker, printer, interval=60.0, stop_event=stop_progress)
    )

    compare_task = asyncio.create_task(
        monitor_compare_dags(
            client,
            outcomes,
            printer=printer,
            tracker=tracker,
            poll_interval=60.0,
            timeout=args.compare_timeout,
        )
    )

    pair_tasks = [
        process_pair(
            client,
            o,
            semaphore=semaphore,
            printer=printer,
            tracker=tracker,
            poll_interval=args.poll_interval,
            timeout=args.timeout,
        )
        for o in outcomes
    ]

    await asyncio.gather(*pair_tasks, return_exceptions=True)

    summary = await tracker.summary_line()
    await printer.emit(summary)
    await printer.emit("All twin/emr pairs done. Waiting for compare DAGs...")

    try:
        await asyncio.wait_for(compare_task, timeout=args.compare_timeout)
    except asyncio.TimeoutError:
        await printer.emit("WARNING: compare monitor timed out", stream=printer.stderr)

    stop_progress.set()
    await progress_task

    print_summary(outcomes)

    has_failures = any(
        o.twin.status == DagStatus.FAILED or o.emr.status == DagStatus.FAILED
        for o in outcomes
    )
    return 1 if has_failures else 0


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    return asyncio.run(async_main(args))


if __name__ == "__main__":
    sys.exit(main())
