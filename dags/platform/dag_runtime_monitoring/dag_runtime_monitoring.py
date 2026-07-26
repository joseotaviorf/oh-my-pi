"""
airflow parsing enforcement

Note: this line above forces Airflow to parse this file for implemented DAGs.

Runtime-anomaly monitor. Every 30 minutes it:

1. Inspects every currently-running DAG run and flags any whose elapsed time is
   anomalous *relative to that same DAG's own recent successful runs*
   (P<percentile> of durations over the last <lookback_days>, times a factor, and
   only past an absolute min-duration floor) — no hardcoded per-DAG time thresholds.
2. Flags DAGs that *should have started by now* (SLA start / missing-run guard)
   based on each DAG's own historical first-start offset within the daily cycle,
   with dependency-based root-cause suppression so one stalled root produces one
   alert instead of hundreds of downstream noise.

Alerting is tiered by ``critical_dags`` (soft-launch: empty list → Chat only):
  * Every over-baseline / missing-run DAG is reported to Google Chat and **tracked
    to closure** (threaded updates while running/missing, final message on resolve).
  * Additionally, *slow* DAGs in ``critical_dags`` **or** that transitively block one
    (via ``dependencies.yaml``) also open a JiraOps on-caller alert once.
  * Missing-run findings are Chat-only (no JiraOps), by design.

Elapsed time and historical baselines for the slowness check are anchored on the
earliest ``execute-job-cluster*`` task start when that task exists for the run
(so sensor / pre-cluster wait is excluded). DAGs without that task keep full
``dag_run`` wall time.

Both alert paths include the transitive list of downstream ``bietlejuice.dw_*`` DAGs
impacted by the slow / missing run, computed each cycle from the deployed
``dependencies.yaml``.

Real alerts are only sent when ``environment == prod`` (or a force_send test); otherwise
the DAG logs what it *would* send (so Forno/local runs still exercise the queries).
"""

from __future__ import annotations

import json
import math
import os
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from typing import Iterable
from urllib.parse import quote

import pendulum
import requests
from airflow import DAG
from airflow.configuration import conf
from airflow.models import Variable
from airflow.operators.python import PythonOperator
from airflow.utils.db import provide_session
from sqlalchemy import bindparam, text

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)
from bietlejuice.base.jiraops.jiraops_client import JiraOpsClient
from bietlejuice.services.configuration_service import ConfigurationService

DAG_NAME = "dag_runtime_monitoring"
DAG_ID = f"bietlejuice.{DAG_NAME}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
AIRFLOW_URL = conf.get("webserver", "base_url")

# Airflow Variables.
JIRA_OPS_VARIABLE = "JIRA_OPS_ONCALL_APIKEY"
DEDUP_VARIABLE_KEY = "DAG_RUNTIME_MONITORING_ALERTED_RUNS"
_KIND_SLOW = "slow"
_KIND_MISSING_RUN = "missing_run"
_SLA_RUN_ID_PREFIX = "sla::"

# Cap the DW blast-radius list in Chat / JiraOps messages.
_IMPACTED_DW_LIST_LIMIT = 25
_UNKNOWN_OWNER = "unknown"
# Channel payload limits (hard caps; truncate before send).
# GChat incoming webhooks reject text > 4096 characters.
_GCHAT_TEXT_MAX = 4096
# Opsgenie / JSM Ops: alert title (message) max 130; description max 15000.
_JIRA_MESSAGE_MAX = 130
_JIRA_DESCRIPTION_MAX = 15000
# Job-cluster bootstrap task (and ``execute-job-cluster-N`` multi-cluster variants).
_EXECUTE_JOB_CLUSTER_TASK_PREFIX = "execute-job-cluster"
_ACCESSORY_TASK_PREFIXES = (
    "optimize",
    "data-quality",
    "sync",
    "register",
    "job-cluster-finished",
    "terminate-emr-cluster",
)
_NOT_ACCESSORY_SQL = " AND ".join(
    f"ti2.task_id NOT LIKE '{p}%'" for p in _ACCESSORY_TASK_PREFIXES
)

# Config fallbacks used when a key is missing from prod_conf.yml / forno_conf.yml.
_DEFAULT_CONFIG = {
    "critical_dags": [],
    "lookback_days": 30,
    "min_history_runs": 15,
    "percentile": 99,
    "factor": 1.5,
    # Absolute floor: only alert on runs that have been executing at least this long,
    # so quick DAGs never page no matter how large their relative swing.
    "min_alert_duration_minutes": 90,
    # SLA start / missing-run guard (Chat-only).
    "sla_enabled": True,
    "sla_lookback_days": 14,
    "sla_min_history_cycles": 10,
    "sla_percentile": 90,
    "sla_grace_minutes": 60,
    # Matches reset_datasets schedule_interval="55 20 * * *" (America/Sao_Paulo).
    "sla_cycle_anchor_local_time": "20:55",
    "sla_exclude_dag_prefixes": ["migration_"],
    "sla_exclude_dag_suffixes": ["__validation"],
}

# Only "real" automatic runs count — scheduled, dataset-triggered, or mediator-triggered.
# Manual/backfill runs resolve to TEST_RUN in DatasetService._get_run_type (prod callbacks
# skip them), so we exclude them from both alerting and the baseline. dag_run.conf is a
# pickled column (not JSON-queryable), so we rely on the native run_type / run_id signals.
_REAL_RUN_FILTER = (
    "(run_type IN ('scheduled', 'dataset_triggered') "
    "OR run_id LIKE 'mediator_trig\\_\\_%' ESCAPE '\\')"
)
_REAL_RUN_FILTER_DR = (
    "(dr.run_type IN ('scheduled', 'dataset_triggered') "
    "OR dr.run_id LIKE 'mediator_trig\\_\\_%' ESCAPE '\\')"
)

# Filter dag_run first, then join task_instance only for those (dag_id, run_id) pairs.
# Never aggregate all execute-job-cluster* TIs — that timed out on the metadata DB (#26399).
_RUNNING_QUERY = text(
    f"""
    WITH running AS (
        SELECT dr.dag_id, dr.run_id, dr.start_date
        FROM dag_run AS dr
        INNER JOIN dag AS d ON d.dag_id = dr.dag_id AND d.is_active = TRUE
        WHERE dr.state = 'running'
          AND dr.start_date IS NOT NULL
          AND dr.dag_id != :self_dag_id
          AND {_REAL_RUN_FILTER_DR}
    )
    SELECT
        r.dag_id,
        r.run_id,
        r.start_date,
        MIN(ti.start_date) AS work_start,
        COUNT(ti.task_id) > 0 AS has_execute_job_cluster,
        EXISTS (
            SELECT 1 FROM task_instance AS ti2
            WHERE ti2.dag_id = r.dag_id AND ti2.run_id = r.run_id
              AND ti2.state IN ('running', 'queued', 'scheduled', 'up_for_retry', 'up_for_reschedule')
              AND {_NOT_ACCESSORY_SQL}
        ) AS has_real_work_running
    FROM running AS r
    LEFT JOIN task_instance AS ti
        ON ti.dag_id = r.dag_id
       AND ti.run_id = r.run_id
       AND ti.task_id LIKE '{_EXECUTE_JOB_CLUSTER_TASK_PREFIX}%'
    GROUP BY r.dag_id, r.run_id, r.start_date
    """
)

# Baseline is built from successful runs that finished within the lookback window
# (end_date >= :since), rather than a fixed count of recent runs. Duration uses the
# earliest execute-job-cluster start when present so baselines match live elapsed.
_HISTORY_QUERY = text(
    f"""
    SELECT
        dr.dag_id,
        EXTRACT(
            EPOCH FROM (
                COALESCE(
                    (SELECT MAX(ti2.end_date) FROM task_instance AS ti2
                     WHERE ti2.dag_id = dr.dag_id AND ti2.run_id = dr.run_id
                       AND {_NOT_ACCESSORY_SQL}),
                    dr.end_date
                ) - COALESCE(MIN(ti.start_date), dr.start_date)
            )
        ) AS duration_s
    FROM dag_run AS dr
    LEFT JOIN task_instance AS ti
        ON ti.dag_id = dr.dag_id
       AND ti.run_id = dr.run_id
       AND ti.task_id LIKE '{_EXECUTE_JOB_CLUSTER_TASK_PREFIX}%'
       AND ti.start_date IS NOT NULL
    WHERE dr.state = 'success'
      AND dr.start_date IS NOT NULL
      AND dr.end_date IS NOT NULL
      AND {_REAL_RUN_FILTER_DR}
      AND dr.dag_id IN :dag_ids
      AND dr.end_date >= :since
    GROUP BY dr.dag_id, dr.run_id, dr.start_date, dr.end_date
    """
).bindparams(bindparam("dag_ids", expanding=True))

# Look up the current state of specific runs we are already tracking (by exact run_id).
_RUN_STATE_QUERY = text(
    f"""
    SELECT
        dr.dag_id,
        dr.run_id,
        dr.state,
        dr.start_date,
        dr.end_date,
        MIN(ti.start_date) AS work_start
    FROM dag_run AS dr
    LEFT JOIN task_instance AS ti
        ON ti.dag_id = dr.dag_id
       AND ti.run_id = dr.run_id
       AND ti.task_id LIKE '{_EXECUTE_JOB_CLUSTER_TASK_PREFIX}%'
    WHERE dr.run_id IN :run_ids AND dr.dag_id IN :dag_ids
    GROUP BY dr.dag_id, dr.run_id, dr.state, dr.start_date, dr.end_date
    """
).bindparams(bindparam("run_ids", expanding=True), bindparam("dag_ids", expanding=True))

_OWNERS_QUERY = text(
    """
    SELECT dag_id, owners
    FROM dag
    WHERE dag_id IN :dag_ids
    """
).bindparams(bindparam("dag_ids", expanding=True))

# SLA start guard — dag / dag_run only (no task_instance; see #26399).
# schedule_interval NULL / 'null' = manual-only (excluded). Dataset DAGs store "Dataset".
_SLA_CANDIDATES_QUERY = text(
    """
    SELECT
        d.dag_id,
        d.schedule_interval
    FROM dag AS d
    WHERE d.is_active = TRUE
      AND d.is_paused = FALSE
      AND d.dag_id != :self_dag_id
      AND d.schedule_interval IS NOT NULL
      AND CAST(d.schedule_interval AS TEXT) != 'null'
    """
)

_SLA_HISTORY_QUERY = text(
    f"""
    SELECT
        dr.dag_id,
        dr.start_date,
        dr.state
    FROM dag_run AS dr
    WHERE dr.start_date IS NOT NULL
      AND dr.start_date >= :since
      AND {_REAL_RUN_FILTER_DR}
      AND dr.dag_id IN :dag_ids
    """
).bindparams(bindparam("dag_ids", expanding=True))

_SLA_STARTED_QUERY = text(
    f"""
    SELECT
        dr.dag_id,
        MIN(dr.start_date) AS first_start
    FROM dag_run AS dr
    WHERE dr.start_date IS NOT NULL
      AND dr.start_date >= :cycle_start
      AND {_REAL_RUN_FILTER_DR}
      AND dr.dag_id IN :dag_ids
    GROUP BY dr.dag_id
    """
).bindparams(bindparam("dag_ids", expanding=True))

# A DagRun in one of these states is finished; anything else is still in flight.
_TERMINAL_STATES = {"success", "failed"}


# --------------------------------------------------------------------------- #
# Pure helpers (no Airflow / DB / network — unit-testable in isolation)
# --------------------------------------------------------------------------- #
def _percentile(values: list, pct: float) -> float:
    """Linear-interpolation percentile (pct in 0..100). Dependency-free."""
    if not values:
        raise ValueError("percentile of an empty sequence is undefined")
    ordered = sorted(values)
    if len(ordered) == 1:
        return float(ordered[0])
    rank = (len(ordered) - 1) * (pct / 100.0)
    low = math.floor(rank)
    high = math.ceil(rank)
    if low == high:
        return float(ordered[int(rank)])
    return float(ordered[low] + (ordered[high] - ordered[low]) * (rank - low))


def _trim_iqr(values: list, *, k: float = 1.5) -> list:
    """Remove outliers outside Tukey fences (Q1 - k*IQR, Q3 + k*IQR)."""
    if len(values) < 4:
        return list(values)
    ordered = sorted(values)
    q1 = _percentile(ordered, 25)
    q3 = _percentile(ordered, 75)
    iqr = q3 - q1
    lo = q1 - k * iqr
    hi = q3 + k * iqr
    return [v for v in ordered if lo <= v <= hi]


def _evaluate_runtime(
    elapsed_s: float,
    history_durations_s: list,
    *,
    percentile: float,
    factor: float,
    min_history: int,
    min_elapsed_s: float = 0,
) -> dict | None:
    """
    Decide whether a running DAG is anomalously slow vs its own recent history.

    Returns a finding dict when ``elapsed_s`` exceeds ``P<percentile> * factor`` of the
    historical durations, else ``None``. Returns ``None`` when there is not enough
    history to form a reliable baseline (avoids false alarms on new/sparse DAGs), or when
    the run has been executing for less than ``min_elapsed_s`` (absolute floor — quick
    DAGs never alert regardless of their relative swing).
    """
    if len(history_durations_s) < min_history:
        return None
    if elapsed_s < min_elapsed_s:
        return None
    baseline = _percentile(_trim_iqr(history_durations_s), percentile)
    if baseline <= 0:
        # A non-positive baseline (e.g. runs that all finish in ~0s) makes the relative
        # threshold meaningless — every positive elapsed time would flag. Skip instead.
        return None
    threshold = baseline * factor
    if elapsed_s <= threshold:
        return None
    pct_over = round((elapsed_s / baseline - 1) * 100)  # baseline > 0 guaranteed above
    return {
        "elapsed_s": float(elapsed_s),
        "baseline_s": baseline,
        "threshold_s": threshold,
        "pct_over": pct_over,
    }


def _format_duration(seconds: float) -> str:
    seconds = int(seconds)
    hours, remainder = divmod(seconds, 3600)
    minutes, secs = divmod(remainder, 60)
    if hours:
        return f"{hours}h{minutes:02d}m"
    if minutes:
        return f"{minutes}m{secs:02d}s"
    return f"{secs}s"


def _run_key(dag_id: str, run_id: str) -> str:
    return f"{dag_id}|{run_id}"


def _resolve_config(raw: dict | None) -> dict:
    """Merge the DAG config over the defaults so missing keys are tolerated."""
    merged = dict(_DEFAULT_CONFIG)
    merged.update(raw or {})
    return merged


def _effective_work_start(row) -> datetime | None:
    """Clock start for elapsed time, or ``None`` to skip (pre-cluster / sensor wait).

    When the run has any ``execute-job-cluster*`` task instance, use its earliest
    ``start_date`` (skip while that is still null). Legacy DAGs without that task
    keep ``dag_run.start_date``.
    """
    if not getattr(row, "has_real_work_running", True):
        return None
    has_ejc = bool(getattr(row, "has_execute_job_cluster", False))
    work_start = getattr(row, "work_start", None)
    if has_ejc:
        return work_start
    return getattr(row, "start_date", None)


def _parse_iso_datetime(value) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _follow_up_clock_start(entry: dict, row) -> datetime | None:
    """Prefer ledger ``work_start_date``, then joined ``work_start``, else dag start."""
    from_ledger = _parse_iso_datetime(entry.get("work_start_date"))
    if from_ledger is not None:
        return from_ledger
    work_start = getattr(row, "work_start", None)
    if work_start is not None:
        return work_start
    return getattr(row, "start_date", None)


def _evaluate_all(
    running_rows, durations_by_dag: dict, now: datetime, config: dict
) -> list:
    """Build findings for every running run that is over its relative baseline.

    Skips runs that have an ``execute-job-cluster*`` TI that has not started yet
    (sensor / pre-cluster wait). Elapsed uses that task's start when present.
    """
    critical = set(config["critical_dags"])
    min_elapsed_s = config["min_alert_duration_minutes"] * 60
    findings = []
    for row in running_rows:
        history = durations_by_dag.get(row.dag_id, [])
        work_start = _effective_work_start(row)
        if work_start is None:
            continue  # waiting on sensors / pre-cluster, or missing start
        elapsed_s = (now - work_start).total_seconds()
        result = _evaluate_runtime(
            elapsed_s,
            history,
            percentile=config["percentile"],
            factor=config["factor"],
            min_history=config["min_history_runs"],
            min_elapsed_s=min_elapsed_s,
        )
        if result is None:
            continue
        result.update(
            dag_id=row.dag_id,
            run_id=row.run_id,
            history_count=len(history),
            percentile=config["percentile"],
            tier="critical" if row.dag_id in critical else "standard",
            work_start_date=work_start.isoformat(),
        )
        findings.append(result)
    return findings


# --------------------------------------------------------------------------- #
# SLA start / missing-run helpers
# --------------------------------------------------------------------------- #
_DEFAULT_SLA_ANCHOR_HHMM = "20:55"


def _parse_anchor_hhmm(hhmm: str) -> tuple[int, int]:
    """Parse ``HH:MM`` into ``(hour, minute)``. Raises ``ValueError`` on bad input."""
    hour_s, minute_s = str(hhmm).strip().split(":", 1)
    hour, minute = int(hour_s), int(minute_s)
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        raise ValueError(f"hour/minute out of range: {hour}:{minute}")
    return hour, minute


def _resolve_anchor_hhmm(
    hhmm: str | None, *, default: str = _DEFAULT_SLA_ANCHOR_HHMM
) -> str:
    """Validate config ``HH:MM``; fall back to ``default`` on bad / empty values.

    Keeps a bad ``sla_cycle_anchor_local_time`` from crashing the whole monitor
    (slowness detection included).
    """
    candidate = str(hhmm).strip() if hhmm is not None else default
    if not candidate:
        candidate = default
    try:
        hour, minute = _parse_anchor_hhmm(candidate)
        return f"{hour:02d}:{minute:02d}"
    except (TypeError, ValueError) as exc:
        print(
            f"⚠️  Invalid sla_cycle_anchor_local_time={hhmm!r}; "
            f"using {default!r} ({exc})"
        )
        return default


def _cycle_anchor(
    moment: datetime,
    *,
    hhmm: str = _DEFAULT_SLA_ANCHOR_HHMM,
    tz=LOCAL_TZ,
) -> datetime:
    """Most recent daily cycle anchor at or before ``moment`` (UTC-aware).

    Anchors the orchestration day at ``hhmm`` in ``tz`` (default 20:55 America/Sao_Paulo,
    matching ``reset_datasets``) so offsets stay monotonic across local/UTC midnight.
    """
    local = pendulum.instance(moment).in_timezone(tz)
    hour, minute = _parse_anchor_hhmm(hhmm)
    candidate = local.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if local < candidate:
        candidate = candidate.subtract(days=1)
    return candidate.in_timezone("UTC")


def _offset_minutes(start: datetime, *, hhmm: str = _DEFAULT_SLA_ANCHOR_HHMM) -> float:
    """Minutes from the cycle anchor that contains ``start`` to ``start``."""
    anchor = _cycle_anchor(start, hhmm=hhmm)
    start_utc = pendulum.instance(start).in_timezone("UTC")
    return (start_utc - anchor).total_seconds() / 60.0


def _sla_run_id(cycle_anchor: datetime) -> str:
    return f"{_SLA_RUN_ID_PREFIX}{cycle_anchor.isoformat()}"


def _is_sla_entry(entry: dict) -> bool:
    return entry.get("kind") == _KIND_MISSING_RUN or str(
        entry.get("run_id") or ""
    ).startswith(_SLA_RUN_ID_PREFIX)


def _matches_exclude_prefix(dag_id: str, prefix: str) -> bool:
    if not prefix:
        return False
    if dag_id.startswith(prefix):
        return True
    return any(part.startswith(prefix) for part in dag_id.split("."))


def _is_sla_candidate(dag_id: str, schedule_interval, config: dict) -> bool:
    """True when a DAG row is eligible for the missing-run guard."""
    if dag_id == DAG_ID:
        return False
    if schedule_interval is None or str(schedule_interval).strip().lower() == "null":
        return False
    for prefix in config.get("sla_exclude_dag_prefixes") or []:
        if _matches_exclude_prefix(dag_id, prefix):
            return False
    for suffix in config.get("sla_exclude_dag_suffixes") or []:
        if suffix and dag_id.endswith(suffix):
            return False
    return True


def _expected_offset_minutes(
    offsets: list,
    *,
    percentile: float,
    min_history: int,
) -> float | None:
    """P-percentile of IQR-trimmed offsets, or None when history is too thin."""
    if len(offsets) < min_history:
        return None
    trimmed = _trim_iqr(offsets)
    if not trimmed:
        return None
    return _percentile(trimmed, percentile)


def _first_starts_by_cycle(
    history_rows: Iterable,
    *,
    hhmm: str,
) -> dict:
    """Map ``dag_id → {cycle_anchor_iso → earliest start_date}`` from history rows."""
    by_dag: dict = {}
    for row in history_rows:
        start = getattr(row, "start_date", None)
        if start is None:
            continue
        dag_id = row.dag_id
        anchor = _cycle_anchor(start, hhmm=hhmm)
        key = anchor.isoformat()
        per_dag = by_dag.setdefault(dag_id, {})
        prev = per_dag.get(key)
        if prev is None or start < prev:
            per_dag[key] = start
    return by_dag


def _offsets_by_dag(first_starts: dict, *, hhmm: str) -> dict:
    """Map ``dag_id → [offset_minutes, ...]`` from per-cycle first starts."""
    offsets: dict = {}
    for dag_id, cycles in first_starts.items():
        offsets[dag_id] = [
            _offset_minutes(start, hhmm=hhmm) for start in cycles.values()
        ]
    return offsets


def _build_upstream_index(dependencies: dict | None) -> dict:
    """``dag_id → {direct upstream dag_ids}`` from ``dependencies.yaml``."""
    if not isinstance(dependencies, dict):
        return {}
    index: dict = {}
    for dependent_dag, upstreams in dependencies.items():
        if upstreams is None:
            continue
        try:
            unique = BietlejuiceDependencyHelper.find_unique_dependencies_in_dependency_object(
                upstreams
            )
        except (ValueError, TypeError):
            continue
        upstream_dags = {
            dep.split(":")[0]
            for dep in unique
            if isinstance(dep, str) and dep.split(":")[0]
        }
        upstream_dags.discard(dependent_dag)
        if upstream_dags:
            index[dependent_dag] = upstream_dags
    return index


def _load_upstream_index_safe() -> dict | None:
    """Load ``dependencies.yaml`` and invert to an upstream index.

    Returns ``None`` when the graph is unavailable so SLA detection can fail closed
    (skip opening new missing-run alerts) instead of treating every late DAG as a
    root with an empty upstream map. A successfully loaded empty file still returns
    ``{}``.
    """
    try:
        deps = BietlejuiceDependencyHelper.read_dependencies()
        if not isinstance(deps, dict):
            return None
        return _build_upstream_index(deps)
    except Exception as exc:  # noqa: BLE001 — operational guard
        print(f"⚠️  Failed to load/index dependencies.yaml for SLA upstreams: {exc}")
        return None


def _select_sla_roots(
    late_dag_ids: set,
    *,
    upstream_index: dict,
    succeeded_this_cycle: set,
    expected_this_cycle: set | None = None,
) -> tuple[list, int, bool]:
    """Return (root dag_ids sorted, suppressed_count, used_fallback).

    A *confirmed* root is a late DAG where no upstream is itself late and every
    upstream that was expected to run this cycle already succeeded. Upstreams outside
    ``expected_this_cycle`` (paused, inactive, or excluded from the guard) cannot be
    waited on, so they never block — otherwise their dependents would be permanently
    unalertable.

    When nothing is confirmed but DAGs *are* late, fall back to the topological tops
    of the late set (no upstream is itself late) and flag it. Reporting a
    lower-confidence root beats going silent on a real cascade, which is the failure
    mode the 2026-07-14 postmortem describes.
    """
    tops = [
        dag_id
        for dag_id in sorted(late_dag_ids)
        if not any(
            upstream in late_dag_ids
            for upstream in (upstream_index.get(dag_id) or set())
        )
    ]
    confirmed = [
        dag_id
        for dag_id in tops
        if not any(
            upstream not in succeeded_this_cycle
            and (expected_this_cycle is None or upstream in expected_this_cycle)
            for upstream in (upstream_index.get(dag_id) or set())
        )
    ]
    roots = confirmed or tops
    return roots, len(late_dag_ids) - len(roots), not confirmed and bool(tops)


def _also_waiting_count(
    root_dag_id: str,
    late_dag_ids: set,
    downstream_index: dict | None,
) -> int:
    """How many other late DAGs sit transitively downstream of ``root_dag_id``."""
    if not late_dag_ids:
        return 0
    index = downstream_index if downstream_index is not None else {}
    downstream = set(
        BietlejuiceDependencyHelper.find_downstream_dags(
            root_dag_id, downstream_index=index
        )
    )
    return len((late_dag_ids & downstream) - {root_dag_id})


def _evaluate_sla_missing_runs(
    candidate_dag_ids: list,
    history_rows: list,
    *,
    now: datetime,
    config: dict,
    upstream_index: dict,
    downstream_index: dict | None,
    expected_dag_ids: set | None = None,
) -> list:
    """Build ``missing_run`` findings for late roots past their due_at.

    ``candidate_dag_ids`` are the DAGs evaluated for lateness; ``expected_dag_ids``
    is the full eligible universe used to decide which upstreams can be waited on.
    They differ only under the ``only_dags`` debug filter, where narrowing the
    evaluation must not make active upstreams look unexpected.

    Returns findings with ``kind=_KIND_MISSING_RUN``. Empty when SLA is disabled or
    nothing is past due.
    """
    if not config.get("sla_enabled", True) or not candidate_dag_ids:
        return []

    hhmm = _resolve_anchor_hhmm(config.get("sla_cycle_anchor_local_time"))
    percentile = float(config.get("sla_percentile", 90))
    min_history = int(config.get("sla_min_history_cycles", 10))
    grace_minutes = float(config.get("sla_grace_minutes", 60))
    lookback_label = int(config.get("sla_lookback_days", 14))

    cycle_start = _cycle_anchor(now, hhmm=hhmm)
    cycle_key = cycle_start.isoformat()
    first_starts = _first_starts_by_cycle(history_rows, hhmm=hhmm)
    offsets_by_dag = _offsets_by_dag(first_starts, hhmm=hhmm)

    succeeded_this_cycle = {
        row.dag_id
        for row in history_rows
        if getattr(row, "state", None) == "success"
        and getattr(row, "start_date", None) is not None
        and _cycle_anchor(row.start_date, hhmm=hhmm).isoformat() == cycle_key
    }
    started_this_cycle = {
        dag_id for dag_id, cycles in first_starts.items() if cycle_key in cycles
    }

    late: dict = {}
    for dag_id in candidate_dag_ids:
        if dag_id in started_this_cycle:
            continue
        expected = _expected_offset_minutes(
            offsets_by_dag.get(dag_id, []),
            percentile=percentile,
            min_history=min_history,
        )
        if expected is None:
            continue
        due_at = cycle_start + timedelta(minutes=expected + grace_minutes)
        if now <= due_at:
            continue
        late[dag_id] = {
            "expected_offset_minutes": expected,
            "due_at": due_at,
            "history_count": len(offsets_by_dag.get(dag_id, [])),
        }

    if not late:
        return []

    late_ids = set(late)
    roots, suppressed_count, used_fallback = _select_sla_roots(
        late_ids,
        upstream_index=upstream_index,
        succeeded_this_cycle=succeeded_this_cycle,
        expected_this_cycle=(
            set(expected_dag_ids)
            if expected_dag_ids is not None
            else set(candidate_dag_ids)
        ),
    )
    print(
        f"⏰ SLA missing-run: {len(late_ids)} late DAG(s), "
        f"{len(roots)} root(s){' (unconfirmed)' if used_fallback else ''}, "
        f"{suppressed_count} suppressed."
    )

    findings = []
    for dag_id in roots:
        meta = late[dag_id]
        due_at = meta["due_at"]
        late_by_s = (now - due_at).total_seconds()
        expected_start = cycle_start + timedelta(
            minutes=meta["expected_offset_minutes"]
        )
        findings.append(
            {
                "kind": _KIND_MISSING_RUN,
                "dag_id": dag_id,
                "run_id": _sla_run_id(cycle_start),
                "tier": "standard",
                "cycle_anchor": cycle_key,
                "due_at": due_at.isoformat(),
                "expected_start": expected_start.isoformat(),
                "expected_offset_minutes": meta["expected_offset_minutes"],
                "grace_minutes": grace_minutes,
                "late_by_s": late_by_s,
                "elapsed_s": late_by_s,  # reused by shared entry helpers where needed
                "percentile": percentile,
                "history_count": meta["history_count"],
                "lookback_days": lookback_label,
                "also_waiting_count": _also_waiting_count(
                    dag_id, late_ids, downstream_index
                ),
                "late_count": len(late_ids),
                "root_is_fallback": used_fallback,
            }
        )
    return findings


def _trigger_url(dag_id: str) -> str:
    return f"{AIRFLOW_URL}/dags/{quote(dag_id, safe='')}/trigger"


def _build_alert_text(finding: dict) -> str:
    """JiraOps / log description — dispatches by finding kind."""
    if finding.get("kind") == _KIND_MISSING_RUN:
        return _missing_run_initial_text(
            _entry_from_finding(finding), finding.get("late_by_s", 0)
        )
    return _slowness_body(
        finding,
        finding["elapsed_s"],
        headline=f"🐌 *{finding['dag_id']}* running slower than usual",
        include_run=True,
        include_impact=True,
        footer=None,
    )


def _thread_key(dag_id: str, run_id: str) -> str:
    """Google Chat threadKey grouping the whole lifecycle of one run into one thread."""
    return f"rubinho::{_run_key(dag_id, run_id)}"


def _entry_from_finding(finding: dict, first_alert_ts: str | None = None) -> dict:
    """Build the ledger entry (tracking snapshot) for a newly-alerted run."""
    impacted = list(finding.get("impacted_dw_dags") or [])
    kind = finding.get("kind") or _KIND_SLOW
    entry = {
        "kind": kind,
        "dag_id": finding["dag_id"],
        "run_id": finding["run_id"],
        "tier": finding.get("tier") or "standard",
        "first_alert_ts": first_alert_ts,
        "percentile": finding.get("percentile"),
        "history_count": finding.get("history_count"),
        "impacted_dw_dags": impacted,
        "impacted_dw_count": finding.get("impacted_dw_count", len(impacted)),
        "owner": finding.get("owner") or _UNKNOWN_OWNER,
    }
    if kind == _KIND_MISSING_RUN:
        entry.update(
            {
                "cycle_anchor": finding.get("cycle_anchor"),
                "due_at": finding.get("due_at"),
                "expected_start": finding.get("expected_start"),
                "expected_offset_minutes": finding.get("expected_offset_minutes"),
                "grace_minutes": finding.get("grace_minutes"),
                "lookback_days": finding.get("lookback_days"),
                "also_waiting_count": finding.get("also_waiting_count", 0),
                "late_count": finding.get("late_count", 0),
                "root_is_fallback": bool(finding.get("root_is_fallback")),
            }
        )
    else:
        entry.update(
            {
                "baseline_s": finding.get("baseline_s"),
                "threshold_s": finding.get("threshold_s"),
                # ISO start used for elapsed (execute-job-cluster or dag_run); follow-ups reuse it.
                "work_start_date": finding.get("work_start_date"),
            }
        )
    return entry


def _over_pct(elapsed_s: float, baseline_s: float | None) -> int | None:
    if not baseline_s or baseline_s <= 0:
        return None
    return round((elapsed_s / baseline_s - 1) * 100)


def _truncate_text(text: str, max_chars: int) -> str:
    """Hard-cap a string for channel payload limits (keeps a trailing ellipsis)."""
    if max_chars <= 0 or len(text) <= max_chars:
        return text
    if max_chars == 1:
        return "…"
    return text[: max_chars - 1] + "…"


def _owner_label(entry: dict) -> str:
    return (entry.get("owner") or _UNKNOWN_OWNER).strip() or _UNKNOWN_OWNER


def _elapsed_bullet(entry: dict, elapsed_s: float) -> str:
    baseline_s = entry.get("baseline_s")
    over = _over_pct(elapsed_s, baseline_s)
    if baseline_s and over is not None:
        sign = "+" if over >= 0 else ""
        return (
            f"• Elapsed: {_format_duration(elapsed_s)} — "
            f"P{entry.get('percentile')} baseline {_format_duration(baseline_s)} "
            f"({sign}{over}%)"
        )
    return f"• Elapsed: {_format_duration(elapsed_s)} — baseline unavailable"


def _format_impacted_dw_line(
    impacted_dw_dags: list | None, *, limit: int = _IMPACTED_DW_LIST_LIMIT
) -> str:
    """Render the DW blast-radius bullet for Chat / JiraOps (truncated after ``limit``)."""
    dags = list(impacted_dw_dags or [])
    if not dags:
        return "• Impacted DW: none"
    shown = dags[:limit]
    overflow = len(dags) - len(shown)
    listed = ", ".join(shown)
    suffix = f" … and {overflow} more" if overflow > 0 else ""
    return f"• Impacted DW ({len(dags)}): {listed}{suffix}"


def _slowness_body(
    entry: dict,
    elapsed_s: float,
    *,
    headline: str,
    include_run: bool = False,
    include_impact: bool = False,
    blocking_count: int | None = None,
    footer: str | None = None,
) -> str:
    """Shared multiline layout for slowness alerts (Chat + JiraOps)."""
    lines = [
        headline,
        f"• Owner: {_owner_label(entry)}",
        _elapsed_bullet(entry, elapsed_s),
    ]
    if include_run:
        lines.append(f"• Run: {entry.get('run_id')}")
    if include_impact:
        lines.append(_format_impacted_dw_line(entry.get("impacted_dw_dags") or []))
    if isinstance(blocking_count, int) and blocking_count > 0:
        lines.append(f"• Still blocking {blocking_count} dw_* DAG(s)")
    if footer:
        lines.append(footer)
    return "\n".join(lines)


def _format_utc_hhmm(value) -> str:
    """Render a datetime / ISO string as ``HH:MM UTC``."""
    dt = _parse_iso_datetime(value)
    if dt is None:
        return "unknown"
    return pendulum.instance(dt).in_timezone("UTC").format("HH:mm") + " UTC"


def _missing_run_body(
    entry: dict,
    late_by_s: float,
    *,
    headline: str,
    include_details: bool = True,
    footer: str | None = None,
) -> str:
    """Shared multiline layout for missing-run (SLA) alerts."""
    lines = [headline, f"• Owner: {_owner_label(entry)}"]
    if include_details:
        expected = _format_utc_hhmm(entry.get("expected_start"))
        grace = entry.get("grace_minutes")
        pct = entry.get("percentile")
        history = entry.get("history_count")
        lookback = entry.get("lookback_days")
        lines.append(
            f"• Expected by: {_format_utc_hhmm(entry.get('due_at'))} "
            f"(P{pct} start {expected} + {grace:g}m grace, {history} cycles / {lookback}d)"
        )
        lines.append(f"• Late by: {_format_duration(late_by_s)}")
        lines.append(_format_impacted_dw_line(entry.get("impacted_dw_dags") or []))
        also_waiting = entry.get("also_waiting_count") or 0
        if also_waiting:
            lines.append(f"• Also waiting downstream: {also_waiting} DAG(s)")
        if entry.get("root_is_fallback"):
            # No late DAG had all its expected upstreams confirmed successful, so this
            # is the top of the late subgraph rather than a confirmed root.
            lines.append(
                f"• Attribution: unconfirmed root "
                f"({entry.get('late_count') or 0} DAG(s) late this cycle)"
            )
        lines.append(f"• Trigger: {_trigger_url(entry['dag_id'])}")
    else:
        lines.append(f"• Late by: {_format_duration(late_by_s)}")
        also_waiting = entry.get("also_waiting_count")
        if isinstance(also_waiting, int) and also_waiting > 0:
            lines.append(f"• Also waiting downstream: {also_waiting} DAG(s)")
    if footer:
        lines.append(footer)
    return "\n".join(lines)


def _initial_text(entry: dict, elapsed_s: float) -> str:
    if _is_sla_entry(entry):
        return _missing_run_initial_text(entry, elapsed_s)
    return _slowness_body(
        entry,
        elapsed_s,
        headline=f"🐌 *{entry['dag_id']}* running slower than usual",
        include_run=True,
        include_impact=True,
        footer="Tracking until it finishes.",
    )


def _missing_run_initial_text(entry: dict, late_by_s: float) -> str:
    return _missing_run_body(
        entry,
        late_by_s,
        headline=f"⏰ *{entry['dag_id']}* has not started",
        include_details=True,
        footer="Tracking until it starts.",
    )


def _update_text(
    entry: dict, elapsed_s: float, *, impacted_dw_count: int | None = None
) -> str:
    if _is_sla_entry(entry):
        return _missing_run_update_text(
            entry, elapsed_s, also_waiting=entry.get("also_waiting_count")
        )
    count = (
        impacted_dw_count
        if impacted_dw_count is not None
        else entry.get("impacted_dw_count")
    )
    return _slowness_body(
        entry,
        elapsed_s,
        headline=f"🐌 *{entry['dag_id']}* still running",
        blocking_count=count if isinstance(count, int) else None,
    )


def _missing_run_update_text(
    entry: dict, late_by_s: float, *, also_waiting: int | None = None
) -> str:
    if also_waiting is not None:
        entry = {**entry, "also_waiting_count": also_waiting}
    return _missing_run_body(
        entry,
        late_by_s,
        headline=f"⏰ *{entry['dag_id']}* still has not started",
        include_details=False,
    )


def _resolved_text(entry: dict, duration_s: float | None) -> str:
    dur = _format_duration(duration_s) if duration_s is not None else "unknown time"
    return (
        f"✅ *{entry['dag_id']}* finished after {dur} (was flagged as slow).\n"
        f"• Owner: {_owner_label(entry)}"
    )


def _failed_text(entry: dict, duration_s: float | None) -> str:
    dur = _format_duration(duration_s) if duration_s is not None else "unknown time"
    return (
        f"❌ *{entry['dag_id']}* run FAILED after {dur} (was flagged as slow).\n"
        f"• Owner: {_owner_label(entry)}"
    )


def _missing_run_started_text(
    entry: dict, *, started_at: datetime | None, late_by_s: float | None
) -> str:
    started = _format_utc_hhmm(started_at) if started_at is not None else "unknown"
    late = (
        _format_duration(late_by_s)
        if late_by_s is not None and late_by_s >= 0
        else "unknown time"
    )
    return (
        f"✅ *{entry['dag_id']}* started at {started} "
        f"(was {late} past SLA).\n"
        f"• Owner: {_owner_label(entry)}"
    )


def _load_downstream_index_safe() -> dict | None:
    """Load deployed dependencies.yaml and invert to a downstream index.

    Never fail the monitor cycle on read/parse errors or invalid upstream shapes
    (e.g. ``{}`` / dicts without ``any``/``all``), which raise ``ValueError`` inside
    ``find_unique_dependencies_in_dependency_object``.

    Returns ``None`` when the graph is unavailable so follow-ups can keep the
    ledger snapshot instead of treating a load failure as ``Impacted DW DAGs: none``.
    A successfully loaded empty file still returns ``{}``.
    """
    try:
        deps = BietlejuiceDependencyHelper.read_dependencies()
        if not isinstance(deps, dict):
            return None
        return BietlejuiceDependencyHelper.build_downstream_index(deps)
    except Exception as exc:  # noqa: BLE001 — operational guard; keep alerting alive
        print(f"⚠️  Failed to load/index dependencies.yaml for DW impact: {exc}")
        return None


def _enrich_findings_with_dw_impact(
    findings: list, downstream_index: dict | None
) -> None:
    """Attach transitive ``bietlejuice.dw_*`` dependents to each finding in place."""
    if not findings:
        return
    index = downstream_index if downstream_index is not None else {}
    for finding in findings:
        impacted = BietlejuiceDependencyHelper.find_downstream_dw_dags(
            finding["dag_id"], downstream_index=index
        )
        finding["impacted_dw_dags"] = impacted
        finding["impacted_dw_count"] = len(impacted)


def _impacts_critical(
    dag_id: str, critical: set, downstream_index: dict | None
) -> bool:
    """True if ``dag_id`` is in ``critical`` or transitively blocks any critical DAG.

    When ``critical`` is empty, returns False (soft-launch: nothing pages Jira).
    """
    if not critical:
        return False
    if dag_id in critical:
        return True
    index = downstream_index if downstream_index is not None else {}
    downstream = BietlejuiceDependencyHelper.find_downstream_dags(
        dag_id, downstream_index=index
    )
    return bool(critical.intersection(downstream))


def _assign_alert_tiers(
    findings: list, critical_dags, downstream_index: dict | None
) -> None:
    """Set ``tier`` on each finding for Chat vs Chat+JiraOps routing.

    * Empty ``critical_dags`` → all ``standard`` (Chat only; soft-launch).
    * Non-empty → ``critical`` (Chat + JiraOps) if the DAG is in the set or
      transitively blocks one; otherwise ``standard`` (Chat only).
    """
    critical = set(critical_dags or ())
    for finding in findings:
        if _impacts_critical(finding["dag_id"], critical, downstream_index):
            finding["tier"] = "critical"
        else:
            finding["tier"] = "standard"


def _live_impacted_dw_count(dag_id: str, downstream_index: dict | None) -> int | None:
    """Recompute DW blast-radius count from the live graph for follow-up updates.

    Returns ``None`` when ``downstream_index`` is unavailable so callers fall back
    to the ledger's ``impacted_dw_count`` instead of forcing ``0``.
    """
    if downstream_index is None:
        return None
    return len(
        BietlejuiceDependencyHelper.find_downstream_dw_dags(
            dag_id, downstream_index=downstream_index
        )
    )


# --------------------------------------------------------------------------- #
# Side-effecting senders
# --------------------------------------------------------------------------- #
def _send_jira_alert(
    finding: dict,
    responder_team_id: str | None = None,
    test: bool = False,
) -> bool:
    """Page JiraOps for one critical DAG. Returns True only when delivery succeeded.

    ``responder_team_id`` overrides the default (Data Engineering) team — used to route a
    test alert to a test team. ``test`` marks the alert as a test (prefix + ``test`` tag).
    """
    dag_id = finding.get("dag_id", "<unknown>")
    run_id = finding.get("run_id", "<unknown>")
    tags = [dag_id, "runtime anomaly", "critical"]
    if test:
        tags.append("test")
    try:
        # Title/description must stay inside try: a bad finding must not abort the
        # whole monitor_dag_runtimes task — log and skip this page instead.
        title = _truncate_text(
            f"{'[TEST] ' if test else ''}DAG runtime anomaly: {dag_id}",
            _JIRA_MESSAGE_MAX,
        )
        description = _truncate_text(_build_alert_text(finding), _JIRA_DESCRIPTION_MAX)
        creds = json.loads(Variable.get(JIRA_OPS_VARIABLE))
        client = JiraOpsClient(creds)
        response = client.create_alert(
            message=title,
            description=description,
            tags=tags,
            extra_properties={
                "DAG": dag_id,
                "RunId": run_id,
                "DAGOwner": _owner_label(finding),
                "PctOverBaseline": finding["pct_over"],
            },
            responder_team_id=responder_team_id,
            alias=f"dag-runtime-{dag_id}-{run_id}",
        )
        response.raise_for_status()
    except Exception as error:  # noqa: BLE001 - best-effort alerting, keep going
        print(
            f"❌ Failed to create JiraOps alert for {dag_id} (run {run_id}): {error}. "
            "Will retry on the next cycle while the run is still slow."
        )
        return False
    print(f"✅ JiraOps alert created for {dag_id} (run {run_id}).")
    return True


def _post_gchat(webhook_url: str | None, text_content: str, thread_key: str) -> bool:
    """Post one Google Chat message into the run's thread. Returns True on success.

    Uses a direct webhook POST (like notify_stale_dags) so we can set a threadKey —
    the initial alert, all updates, and the closing message for one run land in the same
    Chat thread. Best-effort: logs and returns False on failure. Text is capped at
    ``_GCHAT_TEXT_MAX`` (webhook hard limit).
    """
    if not webhook_url:
        print(
            "⚠️  gchat webhook not configured "
            f"(Variable behind notification_webhooks_keys.{DAG_NAME}). "
            "Skipping gchat message."
        )
        return False
    separator = "&" if "?" in webhook_url else "?"
    url = f"{webhook_url}{separator}messageReplyOption=REPLY_MESSAGE_FALLBACK_TO_NEW_THREAD"
    payload = {
        "text": _truncate_text(text_content, _GCHAT_TEXT_MAX),
        "thread": {"threadKey": thread_key},
    }
    try:
        response = requests.post(url, json=payload)
        response.raise_for_status()
    except Exception as error:  # noqa: BLE001 - best-effort alerting, keep going
        print(f"❌ gchat post failed (thread {thread_key}): {error}.")
        return False
    return True


# --------------------------------------------------------------------------- #
# DB access
# --------------------------------------------------------------------------- #
def _fetch_running_runs(session):
    return session.execute(_RUNNING_QUERY, {"self_dag_id": DAG_ID}).fetchall()


def _fetch_recent_durations(session, dag_ids: list, since: datetime) -> dict:
    if not dag_ids:
        return {}
    rows = session.execute(
        _HISTORY_QUERY, {"dag_ids": list(dag_ids), "since": since}
    ).fetchall()
    durations: dict = {}
    for row in rows:
        durations.setdefault(row.dag_id, []).append(float(row.duration_s))
    return durations


def _primary_owner(raw: str | None) -> str | None:
    """First owner from a comma-separated Airflow owners string (or None if empty)."""
    if not raw or not str(raw).strip():
        return None
    primary = str(raw).split(",")[0].strip()
    return primary or None


def _owner_from_serialized_dag(session, dag_id: str) -> str | None:
    """Resolve owner from ``serialized_dag`` when ``dag.owners`` is blank.

    On Astro/Airflow the Details UI ``Owners`` field maps to ``dag.owners``, which is
    often empty even though tasks inherit ``default_args.owner`` (visible after
    deserializing the DAG). Prefer the aggregated ``SerializedDAG.owner``.
    """
    try:
        from airflow.models.serialized_dag import SerializedDagModel

        model = SerializedDagModel.get(dag_id, session=session)
        if not model or not model.dag:
            return None
        return _primary_owner(model.dag.owner)
    except Exception as exc:  # noqa: BLE001 — best-effort; never fail the monitor
        print(f"⚠️  Failed to resolve owner from serialized_dag for {dag_id}: {exc}")
        return None


def _fetch_dag_owners(session, dag_ids) -> dict:
    """Batch-load DAG owners keyed by dag_id (``dag.owners``, then serialized DAG)."""
    if not dag_ids:
        return {}
    wanted = list(dag_ids)
    rows = session.execute(_OWNERS_QUERY, {"dag_ids": wanted}).fetchall()
    owners = {}
    missing = []
    for row in rows:
        primary = _primary_owner(row.owners)
        if primary:
            owners[row.dag_id] = primary
        else:
            missing.append(row.dag_id)
    seen = {row.dag_id for row in rows}
    missing.extend(dag_id for dag_id in wanted if dag_id not in seen)

    for dag_id in missing:
        owners[dag_id] = _owner_from_serialized_dag(session, dag_id) or _UNKNOWN_OWNER

    for dag_id in wanted:
        owners.setdefault(dag_id, _UNKNOWN_OWNER)
    return owners


def _attach_owners(findings: list, owners_by_dag: dict) -> None:
    for finding in findings:
        finding["owner"] = owners_by_dag.get(finding["dag_id"], _UNKNOWN_OWNER)


def _backfill_ledger_owners(ledger: dict, owners_by_dag: dict) -> None:
    for entry in ledger.values():
        if not entry.get("owner"):
            entry["owner"] = owners_by_dag.get(entry["dag_id"], _UNKNOWN_OWNER)


def _fetch_run_states(session, entries: list) -> dict:
    """Look up the current DagRun state/start/end for the tracked runs.

    Returns a mapping ``(dag_id, run_id) -> row`` for the exact pairs we track (the
    IN×IN query can over-match across dags, so we filter to the wanted pairs).
    """
    if not entries:
        return {}
    run_ids = list({e["run_id"] for e in entries})
    dag_ids = list({e["dag_id"] for e in entries})
    rows = session.execute(
        _RUN_STATE_QUERY, {"run_ids": run_ids, "dag_ids": dag_ids}
    ).fetchall()
    wanted = {(e["dag_id"], e["run_id"]) for e in entries}
    return {
        (row.dag_id, row.run_id): row
        for row in rows
        if (row.dag_id, row.run_id) in wanted
    }


def _fetch_sla_candidates(session, config: dict) -> list:
    """Active, scheduled DAG ids eligible for the missing-run guard."""
    rows = session.execute(_SLA_CANDIDATES_QUERY, {"self_dag_id": DAG_ID}).fetchall()
    return [
        row.dag_id
        for row in rows
        if _is_sla_candidate(row.dag_id, row.schedule_interval, config)
    ]


def _fetch_sla_history(session, dag_ids: list, since: datetime) -> list:
    if not dag_ids:
        return []
    return session.execute(
        _SLA_HISTORY_QUERY, {"dag_ids": list(dag_ids), "since": since}
    ).fetchall()


def _fetch_sla_started(session, dag_ids: list, cycle_start: datetime) -> dict:
    """Map ``dag_id → first automatic start_date`` in the current cycle."""
    if not dag_ids:
        return {}
    rows = session.execute(
        _SLA_STARTED_QUERY,
        {"dag_ids": list(dag_ids), "cycle_start": cycle_start},
    ).fetchall()
    return {row.dag_id: row.first_start for row in rows}


# --------------------------------------------------------------------------- #
# On-demand test mode (driven by dag_run.conf on a manual trigger)
# --------------------------------------------------------------------------- #
def _as_str_list(value) -> list | None:
    """Coerce a conf value into a list of strings (or None).

    Trigger conf is arbitrary JSON, so a caller may pass a single string, a list, or
    something invalid. A bare string becomes a one-element list (rather than being
    iterated character-by-character); anything that isn't a str/list/tuple is ignored.
    """
    if value is None:
        return None
    if isinstance(value, str):
        return [value]
    if isinstance(value, (list, tuple)):
        return [str(item) for item in value]
    return None


def _parse_test_options(conf: dict | None) -> dict:
    """Normalize the test/simulation options passed via a manual trigger's conf.

    All keys are optional; an empty conf yields normal scheduled behavior. ``dry_run``
    defaults to True for a bare ``{"simulate": true}`` (so simulation never delivers by
    accident), but to False when ``force_send`` is set — forcing a send clearly intends
    delivery. An explicit ``dry_run`` always wins.
    """
    conf = conf if isinstance(conf, dict) else {}
    simulate = bool(conf.get("simulate", False))
    force_send = bool(conf.get("force_send", False))
    return {
        "simulate": simulate,
        "simulate_dags": _as_str_list(conf.get("simulate_dags")),
        "simulate_state": conf.get("simulate_state") or None,
        "simulate_missing_runs": bool(conf.get("simulate_missing_runs", False)),
        "dry_run": bool(conf.get("dry_run", simulate and not force_send)),
        "force_send": force_send,
        "test_webhook": conf.get("test_webhook"),
        "test_responder_team_id": conf.get("test_responder_team_id"),
        "only_dags": _as_str_list(conf.get("only_dags")),
        # Optional override of YAML critical_dags for this run only.
        "critical_dags": _as_str_list(conf.get("critical_dags")),
    }


def _synthetic_findings(config: dict, dag_ids: list | None = None) -> list:
    """Fabricate findings (same shape as _evaluate_all) so the alert path can run without
    a real slow DAG. Defaults to one critical + one standard id so both tiers fire."""
    critical = set(config["critical_dags"])
    if not dag_ids:
        sample_critical = next(
            iter(config["critical_dags"]), "bietlejuice.__simulated_critical__"
        )
        dag_ids = [sample_critical, "bietlejuice.__simulated_standard__"]
    baseline_s = 1500.0  # 25m
    elapsed_s = 3600.0  # 60m
    return [
        {
            "kind": _KIND_SLOW,
            "elapsed_s": elapsed_s,
            "baseline_s": baseline_s,
            "threshold_s": baseline_s * config["factor"],
            "pct_over": round((elapsed_s / baseline_s - 1) * 100),
            "dag_id": dag_id,
            "run_id": f"simulated__{dag_id}",
            "history_count": config["min_history_runs"],
            "percentile": config["percentile"],
            "tier": "critical" if dag_id in critical else "standard",
        }
        for dag_id in dag_ids
    ]


def _synthetic_missing_run_findings(config: dict, dag_ids: list | None = None) -> list:
    """Fabricate ``missing_run`` findings for simulate_missing_runs mode."""
    if not dag_ids:
        dag_ids = ["bietlejuice.__simulated_missing__"]
    hhmm = _resolve_anchor_hhmm(config.get("sla_cycle_anchor_local_time"))
    now = datetime.now(timezone.utc)
    cycle_start = _cycle_anchor(now, hhmm=hhmm)
    expected_offset = 240.0
    grace = float(config.get("sla_grace_minutes", 60))
    due_at = cycle_start + timedelta(minutes=expected_offset + grace)
    expected_start = cycle_start + timedelta(minutes=expected_offset)
    late_by_s = max((now - due_at).total_seconds(), 3600.0)
    return [
        {
            "kind": _KIND_MISSING_RUN,
            "dag_id": dag_id,
            "run_id": _sla_run_id(cycle_start),
            "tier": "standard",
            "cycle_anchor": cycle_start.isoformat(),
            "due_at": due_at.isoformat(),
            "expected_start": expected_start.isoformat(),
            "expected_offset_minutes": expected_offset,
            "grace_minutes": grace,
            "late_by_s": late_by_s,
            "elapsed_s": late_by_s,
            "percentile": config.get("sla_percentile", 90),
            "history_count": config.get("sla_min_history_cycles", 10),
            "lookback_days": config.get("sla_lookback_days", 14),
            "also_waiting_count": 3,
            "late_count": 4,
            "root_is_fallback": False,
        }
        for dag_id in dag_ids
    ]


def _load_dedup_state() -> dict:
    """Read the dedup state Variable, tolerating a missing/corrupt/non-object value.

    The value is operator-editable, so guard against invalid JSON or a non-mapping
    (null/array/scalar) — any of which would otherwise break `in` / item-assignment.
    """
    try:
        raw = json.loads(Variable.get(DEDUP_VARIABLE_KEY, default_var="{}"))
    except (ValueError, TypeError):
        raw = None
    return raw if isinstance(raw, dict) else {}


def _normalize_ledger(raw: dict, critical_dags=None) -> dict:
    """Coerce the stored ledger into {run_key: entry-dict}.

    Back-compat: an older ledger stored a bare timestamp string per key (both tiers, no
    tier field). Upgrade those using ``critical_dags`` so in-flight critical runs keep
    the Jira-only path and do not get gchat follow-ups. No baseline snapshot — updates
    just omit the % detail.

    Partial/operator-edited dict entries (``{}`` or missing ``dag_id``/``run_id``) are
    repaired from the run_key so ``_fetch_run_states`` never KeyErrors on a bad Variable.
    ``kind`` defaults to ``slow`` so pre-SLA ledger entries keep the slowness follow-up path.
    """
    critical = set(critical_dags or ())
    ledger = {}
    for run_key, value in raw.items():
        dag_id, _, run_id = run_key.partition("|")
        default_tier = "critical" if dag_id in critical else "standard"
        default_kind = (
            _KIND_MISSING_RUN
            if str(run_id).startswith(_SLA_RUN_ID_PREFIX)
            else _KIND_SLOW
        )
        if isinstance(value, dict):
            entry = dict(value)
            entry.setdefault("dag_id", dag_id)
            entry.setdefault("run_id", run_id)
            entry.setdefault("tier", default_tier)
            entry.setdefault("kind", default_kind)
            ledger[run_key] = entry
        else:
            ledger[run_key] = {
                "dag_id": dag_id,
                "run_id": run_id,
                "tier": default_tier,
                "kind": default_kind,
                "first_alert_ts": value if isinstance(value, str) else None,
            }
    return ledger


def _save_ledger(ledger: dict) -> None:
    Variable.set(DEDUP_VARIABLE_KEY, json.dumps(ledger))


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #
@provide_session
def monitor_dag_runtimes(session=None, run_conf=None, **context):
    # NOTE: do not name a parameter `conf` — Airflow's task context injects `conf`
    # (the global AirflowConfigParser) as a kwarg, which would shadow the trigger conf.
    # The manual-trigger payload lives on dag_run.conf. `run_conf` lets tests inject it.
    if run_conf is None:
        dag_run = context.get("dag_run")
        run_conf = getattr(dag_run, "conf", None) or {}
    opts = _parse_test_options(run_conf)

    service = ConfigurationService(dag_name=DAG_NAME)
    config = _resolve_config(service.get_config(DAG_NAME))
    if opts["critical_dags"] is not None:
        config["critical_dags"] = opts["critical_dags"]
    webhook_key = service.get_config("notification_webhooks_keys").get(DAG_NAME)
    webhook_url = Variable.get(webhook_key, default_var=None) if webhook_key else None
    environment = Variable.get("environment", default_var="local")

    print(
        "dag_runtime_monitoring diagnostics: "
        f"environment={environment}, "
        f"ENVIRONMENT={os.environ.get('ENVIRONMENT', '(unset)')}, "
        f"critical_dags={len(config['critical_dags'])}, "
        f"percentile=P{config['percentile']}, factor={config['factor']}, "
        f"lookback_days={config['lookback_days']}, "
        f"min_history_runs={config['min_history_runs']}, "
        f"min_alert_duration_minutes={config['min_alert_duration_minutes']}, "
        f"sla_enabled={config.get('sla_enabled')}, "
        f"sla_lookback_days={config.get('sla_lookback_days')}, "
        f"sla_grace_minutes={config.get('sla_grace_minutes')}, "
        f"webhook_configured={'yes' if webhook_url else 'no'}, "
        # test_webhook value redacted so a throwaway URL never lands in logs
        f"test={{simulate:{opts['simulate']}, "
        f"simulate_missing_runs:{opts['simulate_missing_runs']}, "
        f"dry_run:{opts['dry_run']}, "
        f"force_send:{opts['force_send']}, test_webhook:{'yes' if opts['test_webhook'] else 'no'}, "
        f"test_team:{'yes' if opts['test_responder_team_id'] else 'no'}, "
        f"only_dags:{len(opts['only_dags']) if opts['only_dags'] else 0}, "
        f"critical_override:{'yes' if opts['critical_dags'] is not None else 'no'}}}"
    )

    # Test-destination overrides (test_webhook / test_responder_team_id) only apply to a
    # force_send test delivery — never to a real prod run, which uses the configured
    # webhook and the default on-call team.
    is_test = opts["force_send"]
    gchat_dest = (opts["test_webhook"] if is_test else None) or webhook_url
    jira_team = opts["test_responder_team_id"] if is_test else None
    deliver = (environment == "prod") or opts["force_send"]
    now = datetime.now(timezone.utc)

    downstream_index = _load_downstream_index_safe()

    # --- Simulate: fabricate findings and post a chosen lifecycle phase (no DB / ledger).
    # simulate_state drives which message to emit for the SAME synthetic thread, so a few
    # manual triggers walk the whole lifecycle: (unset)=initial → running → success/failed.
    # simulate_missing_runs switches the synthetic findings to the SLA missing-run shape.
    if opts["simulate"]:
        if opts["simulate_missing_runs"]:
            findings = _synthetic_missing_run_findings(config, opts["simulate_dags"])
            _enrich_findings_with_dw_impact(findings, downstream_index)
            _attach_owners(
                findings,
                _fetch_dag_owners(session, {f["dag_id"] for f in findings}),
            )
            state = opts["simulate_state"]
            print(
                f"🧪 simulate missing-run mode ({state or 'initial'}): "
                f"fabricated {len(findings)} synthetic finding(s)."
            )
            for f in findings:
                print(f"   • [missing_run] {_build_alert_text(f)}")
            if opts["dry_run"] or not deliver:
                print("ℹ️  Not delivering (simulate dry-run / gate). Logging only.")
                return
            if not state:
                for finding in findings:
                    _deliver_initial(finding, gchat_dest, jira_team, is_test)
                return
            ledger = {}
            for finding in findings:
                key = _run_key(finding["dag_id"], finding["run_id"])
                ledger[key] = _entry_from_finding(finding)
            if state == "started":
                started = {f["dag_id"]: now - timedelta(minutes=5) for f in findings}
                _apply_sla_follow_up(ledger, started, gchat_dest, now, config)
            else:
                # "running" / anything else → still-missing update
                _apply_sla_follow_up(ledger, {}, gchat_dest, now, config)
            return

        findings = _synthetic_findings(config, opts["simulate_dags"])
        _enrich_findings_with_dw_impact(findings, downstream_index)
        _assign_alert_tiers(findings, config["critical_dags"], downstream_index)
        _attach_owners(
            findings,
            _fetch_dag_owners(session, {f["dag_id"] for f in findings}),
        )
        state = opts["simulate_state"]
        print(
            f"🧪 simulate mode ({state or 'initial'}): "
            f"fabricated {len(findings)} synthetic finding(s)."
        )
        for f in findings:
            print(f"   • [{f['tier']}] {_build_alert_text(f)}")
        if opts["dry_run"] or not deliver:
            print("ℹ️  Not delivering (simulate dry-run / gate). Logging only.")
            return
        if not state:
            for finding in findings:
                _deliver_initial(finding, gchat_dest, jira_team, is_test)
            return
        # Follow-up phase: build a throwaway ledger + fabricated run states and run the
        # real follow-up logic (Chat lifecycle for every tier).
        ledger = {}
        states = {}
        terminal = state in _TERMINAL_STATES
        for finding in findings:
            key = _run_key(finding["dag_id"], finding["run_id"])
            ledger[key] = _entry_from_finding(finding)
            states[(finding["dag_id"], finding["run_id"])] = SimpleNamespace(
                dag_id=finding["dag_id"],
                run_id=finding["run_id"],
                state=state,
                start_date=now - timedelta(hours=2),
                end_date=now if terminal else None,
            )
        _apply_follow_up(ledger, states, gchat_dest, now, downstream_index)
        return

    # --- Real run: evaluate current anomalies + follow up everything we're tracking ---
    all_running_rows = _fetch_running_runs(session)
    running_rows = all_running_rows
    if opts["only_dags"]:
        wanted = set(opts["only_dags"])
        running_rows = [row for row in all_running_rows if row.dag_id in wanted]

    findings = []
    if running_rows:
        since = now - timedelta(days=config["lookback_days"])
        durations_by_dag = _fetch_recent_durations(
            session, {row.dag_id for row in running_rows}, since
        )
        findings = _evaluate_all(running_rows, durations_by_dag, now, config)
    _assign_alert_tiers(findings, config["critical_dags"], downstream_index)

    # Resolved once per cycle: missing-run detection needs the eligible set, and
    # follow-up needs it to stop tracking DAGs that left it (paused/deactivated).
    sla_enabled = config.get("sla_enabled", True)
    sla_candidates = _fetch_sla_candidates(session, config) if sla_enabled else []
    sla_findings = (
        _collect_sla_findings(
            session,
            config,
            now,
            downstream_index,
            candidates=sla_candidates,
            only_dags=opts["only_dags"],
        )
        if sla_enabled
        else []
    )

    all_findings = findings + sla_findings
    _enrich_findings_with_dw_impact(all_findings, downstream_index)
    ledger = _normalize_ledger(
        _load_dedup_state(), critical_dags=config["critical_dags"]
    )
    owners_by_dag = _fetch_dag_owners(
        session,
        {f["dag_id"] for f in all_findings} | {e["dag_id"] for e in ledger.values()},
    )
    _attach_owners(all_findings, owners_by_dag)
    _backfill_ledger_owners(ledger, owners_by_dag)
    for f in findings:
        print(f"   • [{f['tier']}] {_build_alert_text(f)}")
    for f in sla_findings:
        print(f"   • [missing_run] {_build_alert_text(f)}")
    print(
        f"⏱️ {len(findings)} anomalous run(s); "
        f"⏰ {len(sla_findings)} missing-run root(s); "
        f"tracking {len(ledger)} run(s) for follow-up."
    )

    if opts["dry_run"] or not deliver:
        reason = (
            "dry_run"
            if opts["dry_run"]
            else f"environment={environment} and force_send=false"
        )
        print(f"ℹ️  Not delivering ({reason}); no messages sent, ledger unchanged.")
        return

    # 1) Follow up runs we are already tracking (before opening new ones, so a run that is
    #    both still-anomalous and already tracked gets exactly one update this cycle).
    # Snapshot keys first: follow-up drops terminals from the ledger, but findings were
    # built from the earlier running snapshot — without this, step 2 would re-open the
    # same run (fresh gchat / Jira page) in the same cycle after closure.
    already_tracked = set(ledger)
    _follow_up_tracked_runs(
        session,
        ledger,
        gchat_dest,
        now,
        downstream_index,
        config,
        sla_candidates=sla_candidates,
    )

    # 2) Open new incidents for anomalies not yet tracked (and not just closed above).
    for finding in all_findings:
        key = _run_key(finding["dag_id"], finding["run_id"])
        if key in ledger or key in already_tracked:
            continue
        entry = _entry_from_finding(finding, first_alert_ts=now.isoformat())
        # Every anomaly goes to Chat (lifecycle). Critical *slow* tier also pages JiraOps.
        # Missing-run findings are Chat-only.
        # Gate ledger on *all* required deliveries: if Chat succeeds but Jira fails,
        # do not track yet — otherwise later cycles skip the finding and on-call is
        # never paged despite _send_jira_alert's "retry next cycle" log.
        jira_ok = True
        if finding.get("kind") != _KIND_MISSING_RUN and finding["tier"] == "critical":
            if is_test and not jira_team:
                print(
                    f"⚠️  Refusing to page real on-call from a test trigger for "
                    f"{finding['dag_id']} — pass test_responder_team_id. "
                    f"Chat alert still sent."
                )
            else:
                jira_ok = _send_jira_alert(
                    finding, responder_team_id=jira_team, test=is_test
                )
        chat_ok = _post_gchat(
            gchat_dest,
            _initial_text(
                entry, finding.get("elapsed_s") or finding.get("late_by_s") or 0
            ),
            _thread_key(finding["dag_id"], finding["run_id"]),
        )
        if jira_ok and chat_ok:
            ledger[key] = entry

    _save_ledger(ledger)


def _collect_sla_findings(
    session,
    config: dict,
    now: datetime,
    downstream_index: dict | None,
    *,
    candidates: list,
    only_dags: list | None = None,
) -> list:
    """Evaluate missing-run roots for this cycle from pre-resolved ``candidates``."""
    # ``only_dags`` scopes which DAGs we evaluate, never which upstreams count as
    # expected — otherwise a scoped run would confirm roots that are still blocked.
    eligible = set(candidates)
    if only_dags:
        wanted = set(only_dags)
        candidates = [dag_id for dag_id in candidates if dag_id in wanted]
    if not candidates:
        print("⏰ SLA missing-run: no eligible candidates.")
        return []

    # Include upstreams of candidates so root suppression can see their success state.
    upstream_index = _load_upstream_index_safe()
    if upstream_index is None:
        print(
            "⚠️  Skipping SLA missing-run detection: "
            "upstream dependency graph unavailable (fail closed)."
        )
        return []

    needed = set(candidates)
    for dag_id in candidates:
        needed.update(upstream_index.get(dag_id) or set())

    since = now - timedelta(days=int(config.get("sla_lookback_days", 14)) + 1)
    history_rows = _fetch_sla_history(session, list(needed), since)
    print(
        f"⏰ SLA missing-run: {len(candidates)} candidate(s), "
        f"{len(needed)} dag(s) in history scope, {len(history_rows)} history row(s)."
    )
    return _evaluate_sla_missing_runs(
        candidates,
        history_rows,
        now=now,
        config=config,
        upstream_index=upstream_index,
        downstream_index=downstream_index,
        expected_dag_ids=eligible,
    )


def _deliver_initial(finding, gchat_dest, jira_team, is_test) -> None:
    """Send the initial alert for one finding (used by simulate mode).

    Chat always; JiraOps additionally for critical *slow* tier (when test team is set).
    """
    if finding.get("kind") != _KIND_MISSING_RUN and finding["tier"] == "critical":
        if is_test and not jira_team:
            print(
                f"⚠️  Refusing to page real on-call from a test trigger for "
                f"{finding['dag_id']} — pass test_responder_team_id. "
                f"Chat alert still sent."
            )
        else:
            _send_jira_alert(finding, responder_team_id=jira_team, test=is_test)
    entry = _entry_from_finding(finding)
    _post_gchat(
        gchat_dest,
        _initial_text(entry, finding.get("elapsed_s") or finding.get("late_by_s") or 0),
        _thread_key(finding["dag_id"], finding["run_id"]),
    )


def _follow_up_tracked_runs(
    session,
    ledger: dict,
    gchat_dest,
    now: datetime,
    downstream_index: dict | None,
    config: dict,
    *,
    sla_candidates: list | None = None,
) -> None:
    """Fetch the current state of tracked runs and apply follow-up messaging."""
    if not ledger:
        return
    slow_entries = [e for e in ledger.values() if not _is_sla_entry(e)]
    if slow_entries:
        states = _fetch_run_states(session, slow_entries)
        _apply_follow_up(ledger, states, gchat_dest, now, downstream_index)
    if not any(_is_sla_entry(e) for e in ledger.values()):
        return

    # A DAG that is no longer eligible (paused, deactivated, newly excluded) or a
    # disabled guard must stop the Chat churn now, rather than at cycle rollover.
    if not config.get("sla_enabled", True):
        _drop_sla_entries(ledger, reason="sla_enabled=false")
        return
    eligible = set(sla_candidates or [])
    _drop_sla_entries(
        ledger,
        reason="no longer an SLA candidate (paused, inactive, or excluded)",
        keep_dag_ids=eligible,
    )
    sla_entries = [e for e in ledger.values() if _is_sla_entry(e)]
    if not sla_entries:
        return

    hhmm = _resolve_anchor_hhmm(config.get("sla_cycle_anchor_local_time"))
    started = _fetch_sla_started(
        session,
        [e["dag_id"] for e in sla_entries],
        _cycle_anchor(now, hhmm=hhmm),
    )
    _apply_sla_follow_up(ledger, started, gchat_dest, now, config)


def _drop_sla_entries(
    ledger: dict, *, reason: str, keep_dag_ids: set | None = None
) -> None:
    """Stop tracking SLA entries (all of them, or those outside ``keep_dag_ids``)."""
    for key, entry in list(ledger.items()):
        if not _is_sla_entry(entry):
            continue
        if keep_dag_ids is not None and entry["dag_id"] in keep_dag_ids:
            continue
        print(f"ℹ️  Dropping SLA tracking for {entry['dag_id']}: {reason}.")
        del ledger[key]


def _apply_follow_up(
    ledger: dict,
    states: dict,
    gchat_dest,
    now: datetime,
    downstream_index: dict | None = None,
) -> None:
    """For each tracked *slow* run, post an update (still running) or a closing message
    (terminal), and drop terminal/vanished runs from the ledger. Mutates ledger in place.

    Every tracked run gets Chat follow-ups (critical tier also had an initial JiraOps
    page; the Chat thread is still tracked to closure).

    Closing posts must succeed before the run is dropped — same delivery gate as the
    initial alert — so a failed ✅/❌ webhook is retried next cycle.

    Elapsed / terminal duration prefer ledger ``work_start_date`` (or joined
    ``work_start``) so Chat follow-ups stay aligned with the job-cluster clock.

    SLA (``missing_run``) entries are ignored here — see ``_apply_sla_follow_up``.
    """
    for key, entry in list(ledger.items()):
        if _is_sla_entry(entry):
            continue
        row = states.get((entry["dag_id"], entry["run_id"]))
        if row is None:
            del ledger[key]  # run row gone → stop tracking
            continue
        clock_start = _follow_up_clock_start(entry, row)
        if row.state in _TERMINAL_STATES:
            duration_s = (
                (row.end_date - clock_start).total_seconds()
                if row.end_date and clock_start
                else None
            )
            text_content = (
                _resolved_text(entry, duration_s)
                if row.state == "success"
                else _failed_text(entry, duration_s)
            )
            if not _post_gchat(
                gchat_dest,
                text_content,
                _thread_key(entry["dag_id"], entry["run_id"]),
            ):
                continue  # keep in ledger; retry closing message next cycle
            del ledger[key]
        elif clock_start is not None:
            elapsed_s = (now - clock_start).total_seconds()
            live_count = _live_impacted_dw_count(entry["dag_id"], downstream_index)
            _post_gchat(
                gchat_dest,
                _update_text(entry, elapsed_s, impacted_dw_count=live_count),
                _thread_key(entry["dag_id"], entry["run_id"]),
            )


def _apply_sla_follow_up(
    ledger: dict,
    started_by_dag: dict,
    gchat_dest,
    now: datetime,
    config: dict,
) -> None:
    """Follow up tracked missing-run entries; mutate ledger in place.

    * Cycle rollover → drop silently (alerts never span cycles).
    * DAG started this cycle → closing ✅ message, then drop (gated on delivery).
    * Still missing → threaded update.
    """
    hhmm = _resolve_anchor_hhmm(config.get("sla_cycle_anchor_local_time"))
    current_anchor = _cycle_anchor(now, hhmm=hhmm).isoformat()
    for key, entry in list(ledger.items()):
        if not _is_sla_entry(entry):
            continue
        entry_anchor = entry.get("cycle_anchor")
        if entry_anchor and entry_anchor != current_anchor:
            del ledger[key]
            continue

        started_at = started_by_dag.get(entry["dag_id"])
        if started_at is not None:
            due_at = _parse_iso_datetime(entry.get("due_at"))
            late_by_s = (
                (started_at - due_at).total_seconds() if due_at is not None else None
            )
            if not _post_gchat(
                gchat_dest,
                _missing_run_started_text(
                    entry, started_at=started_at, late_by_s=late_by_s
                ),
                _thread_key(entry["dag_id"], entry["run_id"]),
            ):
                continue
            del ledger[key]
            continue

        due_at = _parse_iso_datetime(entry.get("due_at"))
        late_by_s = (now - due_at).total_seconds() if due_at is not None else 0.0
        # The originally-late set is only known via the ledger snapshot, so the
        # blast-radius count is carried forward rather than recomputed.
        _post_gchat(
            gchat_dest,
            _missing_run_update_text(
                entry, late_by_s, also_waiting=entry.get("also_waiting_count")
            ),
            _thread_key(entry["dag_id"], entry["run_id"]),
        )


with DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_PLATFORM,
        "start_date": datetime(2026, 7, 16, 0, 0, 0, tzinfo=LOCAL_TZ),
    },
    description=(
        "Every 30 min, flags running DAGs whose elapsed time is anomalous vs their own "
        "recent successful runs, and DAGs that have not started by their historical SLA "
        "window (missing-run guard with dependency root suppression). "
        "Every anomaly goes to Google Chat (tracked to closure); slow DAGs in "
        "critical_dags or that block them also page JiraOps on-caller."
    ),
    schedule="*/30 * * * *",
    catchup=False,
    tags=["monitoring", "platform", "runtime-anomaly", "sla"],
) as dag:
    PythonOperator(
        task_id="monitor_dag_runtimes",
        python_callable=monitor_dag_runtimes,
    )
