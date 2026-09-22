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
   alert instead of hundreds of downstream noise. Each root carries its dataset
   trigger state, which separates a dropped dataset event (the 2026-07-14
   postmortem's stale-SerializedDagModel race) from a genuine wait on an upstream.

The dependency graph is the union of the deployed ``dependencies.yaml`` and the live
dataset-scheduling tables, so namespaces the YAML omits (``quintoml.*``) still suppress
correctly. Missing-run alerts close when the DAG runs automatically *or* publishes a
dataset event, which is how an operator's ``impact_downstream_dependents`` recovery
run — invisible to the automatic-run filter — resolves the thread.

Alerting is tiered by declared criticality (tags criticality:Critical|High):
  * Every over-baseline / missing-run DAG is reported to Google Chat and **tracked
    to closure** (threaded updates while running/missing, final message on resolve).
  * Additionally, *slow* DAGs declaring criticality Critical/High **or** that transitively block one
    (via ``dependencies.yaml``) also open a JiraOps on-caller alert once.
  * Missing-run findings for DAGs declaring criticality Critical/High (membership only — never the
    transitive-blocking expansion) also page JiraOps.
  * Deadline-miss findings for DAGs declaring criticality Critical/High and
    sla_deadline_localtime:<HH:MM> (São Paulo) (membership only) also page JiraOps.

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

import pendulum
import requests
from airflow import DAG
from airflow.models import Variable
from airflow.operators.python import PythonOperator
from airflow.utils.db import provide_session
from sqlalchemy import bindparam, text

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.enums.criticality_enum import (
    CRITICALITY_TAG_PREFIX,
    EFFECTIVE_TIER_TAG_PREFIX,
    SLA_DEADLINE_TAG_PREFIX,
    CriticalityEnum,
)
from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)
from bietlejuice.base.jiraops.jiraops_client import JiraOpsClient
from bietlejuice.services.configuration_service import ConfigurationService

DAG_NAME = "dag_runtime_monitoring"
DAG_ID = f"bietlejuice.{DAG_NAME}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
_BIETLEJUICE_DAG_PREFIX = "bietlejuice."

# Airflow Variables.
JIRA_OPS_VARIABLE = "JIRA_OPS_ONCALL_APIKEY"
DEDUP_VARIABLE_KEY = "DAG_RUNTIME_MONITORING_ALERTED_RUNS"
_KIND_SLOW = "slow"
_KIND_MISSING_RUN = "missing_run"
_KIND_DEADLINE_MISS = "deadline_miss"
_SLA_RUN_ID_PREFIX = "sla::"
_DEADLINE_RUN_ID_PREFIX = "deadline::"

# Cap the DW blast-radius list in Chat / JiraOps messages.
_IMPACTED_DW_LIST_LIMIT = 25
# Dataset URIs are long, so the missing-dataset list is capped much tighter.
_MISSING_DATASET_LIST_LIMIT = 5
_UNKNOWN_OWNER = "unknown"

# Why a dataset-scheduled DAG has no run yet.
#  * dropped_dataset_event — every dataset it waits on is queued, or missing while its
#    producer already succeeded. Airflow silently drops a dataset update that lands
#    while the target DAG's SerializedDagModel is stale and never retro-applies it, so
#    the trigger condition stays permanently short (2026-07-14 postmortem).
#  * waiting_upstream — at least one producer genuinely has not delivered yet.
_VERDICT_DROPPED_EVENT = "dropped_dataset_event"
_VERDICT_WAITING_UPSTREAM = "waiting_upstream"
# BietlejuiceDatasetService schedules a DAG as any(all(<first-run-of-day>), any(
# <reprocessing>)), but dag_schedule_dataset_reference stores a flat dataset list and
# loses that AND/OR structure. Only the first-run-of-day branch gates a normal cycle —
# the reprocessing twins fire solely during a reprocessing run — so counting them makes
# a ready DAG read as blocked (dw_accounts_receivable showed 3/7 while short exactly
# one real dataset).
#
# The required branch is named "<dag_id>:<task_id>" and its reprocessing twin appends
# the variant, so the producer is recoverable from the URI itself when
# task_outlet_dataset_reference has no row for it.
_REPROCESSING_VARIANT = "reprocessing"
_REPROCESSING_URI_SUFFIX = f":{_REPROCESSING_VARIANT}"
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
    # SLA start / missing-run guard (Chat; JiraOps when the DAG is in critical_dags).
    "sla_enabled": True,
    "sla_lookback_days": 14,
    "sla_min_history_cycles": 10,
    "sla_percentile": 90,
    "sla_grace_minutes": 60,
    # Matches reset_datasets schedule_interval="55 20 * * *" (America/Sao_Paulo).
    "sla_cycle_anchor_local_time": "20:55",
    "sla_exclude_dag_prefixes": ["migration_"],
    "sla_exclude_dag_suffixes": ["__validation"],
    # No Chat/Jira alerts for MLOps-owned DAGs. Two shapes: the ML namespaces
    # (quintoml.* floods the channel; wonka.* and wonka_freshness_check are the same
    # platform) and the four MLOps-owned DAGs that live in the bietlejuice namespace.
    # _matches_exclude_prefix matches per dot-separated part, so the __validation
    # twins are covered without listing them.
    "alert_exclude_dag_prefixes": [
        "quintoml",
        "wonka",
        "batch_inference",
        "emlio",
        "enrich_emlio",
        "evidently_ml_monitor",
    ],
    # Blast-radius cap on missing-run roots reported in one tick. The readiness gate
    # already keeps a recovering cascade quiet, but it can only do so while the dataset
    # trigger state is readable — when that read fails the fallback deliberately opens
    # up, and this is what bounds the resulting fan-out.
    "sla_max_missing_run_alerts": 25,
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

_DAG_TAGS_QUERY = text(
    """
    SELECT t.dag_id, t.name
    FROM dag_tag AS t
    WHERE t.name LIKE :criticality_prefix
       OR t.name LIKE :deadline_prefix
       OR t.name LIKE :effective_prefix
    """
)

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

_SLA_SUCCEEDED_QUERY = text(
    f"""
    SELECT dr.dag_id, MIN(dr.end_date) AS first_success
    FROM dag_run AS dr
    WHERE dr.state = 'success' AND dr.end_date IS NOT NULL
      AND dr.end_date >= :cycle_start AND {_REAL_RUN_FILTER_DR}
      AND dr.dag_id IN :dag_ids
    GROUP BY dr.dag_id
    """
).bindparams(bindparam("dag_ids", expanding=True))

# Live dataset-scheduling graph, straight from the metadata DB — the exact edges
# Airflow's own scheduler walks. dependencies.yaml is a static approximation that
# omits whole namespaces (every quintoml.* DAG appears there only as an upstream
# value, never as a dependent key), so those DAGs have no upstreams at all as far as
# root suppression is concerned and always look like their own root.
#
# task_outlet_dataset_reference only holds rows for statically declared outlets, so it
# is empty for DAGs that publish theirs dynamically — an INNER JOIN against it returned
# no edges at all and left this graph silently inert. The join is therefore a LEFT one
# and the URI is selected alongside it, letting the producer be recovered from the URI
# prefix when the reference table has nothing. Self-edges are dropped in Python, where
# both producer sources are already merged.
_DATASET_EDGES_QUERY = text(
    """
    SELECT DISTINCT
        dsdr.dag_id AS dependent_dag_id,
        d.uri AS uri,
        todr.dag_id AS upstream_dag_id
    FROM dag_schedule_dataset_reference AS dsdr
    INNER JOIN dataset AS d
        ON d.id = dsdr.dataset_id
    LEFT JOIN task_outlet_dataset_reference AS todr
        ON todr.dataset_id = dsdr.dataset_id
    """
)

# Per-DAG dataset trigger state, scoped to the late set. A dataset_dag_run_queue row
# means "this dataset is satisfied and pending for that DAG"; rows are only consumed
# when a run is actually created, so a DAG that never ran still exposes its partial
# queue — the difference against dag_schedule_dataset_reference names the dataset
# whose update went missing. DISTINCT collapses the per-task duplicates that
# task_outlet_dataset_reference produces when several tasks emit the same dataset.
_DATASET_SATISFACTION_QUERY = text(
    """
    SELECT DISTINCT
        dsdr.dag_id AS dag_id,
        d.uri AS uri,
        CASE WHEN ddrq.target_dag_id IS NULL THEN 0 ELSE 1 END AS satisfied,
        todr.dag_id AS producer_dag_id
    FROM dag_schedule_dataset_reference AS dsdr
    INNER JOIN dataset AS d
        ON d.id = dsdr.dataset_id
    LEFT JOIN dataset_dag_run_queue AS ddrq
        ON ddrq.dataset_id = dsdr.dataset_id
       AND ddrq.target_dag_id = dsdr.dag_id
    LEFT JOIN task_outlet_dataset_reference AS todr
        ON todr.dataset_id = dsdr.dataset_id
    WHERE dsdr.dag_id IN :dag_ids
    """
).bindparams(bindparam("dag_ids", expanding=True))

# Outbound dataset emission for the current cycle. Manual runs are excluded from
# _REAL_RUN_FILTER_DR by design, but a manual trigger is the sanctioned remediation
# for a dropped dataset event — and only one carrying run_type=impact_downstream_
# dependents actually unblocks the chain (a bare one resolves to TEST_RUN and emits
# nothing). Emission is therefore the honest "it really started" signal.
# Cheap despite the missing standalone timestamp index (Airflow only indexes
# (dataset_id, timestamp)): reset_datasets truncates dataset_event at 20:55, the same
# instant as the cycle anchor, so the table never holds more than one cycle. Not
# filtered by dag_id either — one row per emitting DAG beats an IN list over ~1k ids.
_SLA_EMITTED_QUERY = text(
    """
    SELECT
        de.source_dag_id AS dag_id,
        MIN(de.timestamp) AS first_emit
    FROM dataset_event AS de
    WHERE de.timestamp >= :cycle_start
      AND de.source_dag_id IS NOT NULL
    GROUP BY de.source_dag_id
    """
)

# The same one-cycle table, read at dataset granularity. Which *URIs* fired is what
# separates a dropped event from an upstream that simply has not got there yet; the
# source dag_id above cannot, because a producer emits its outlets progressively.
_SLA_EMITTED_URIS_QUERY = text(
    """
    SELECT DISTINCT d.uri AS uri
    FROM dataset_event AS de
    INNER JOIN dataset AS d
        ON d.id = de.dataset_id
    WHERE de.timestamp >= :cycle_start
    """
)

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
        if _is_alert_excluded_dag(row.dag_id, config):
            continue
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


def _deadline_run_id(cycle_anchor: datetime) -> str:
    return f"{_DEADLINE_RUN_ID_PREFIX}{cycle_anchor.isoformat()}"


def _deadline_at(cycle_start: datetime, hhmm_local: str) -> datetime:
    hour, minute = _parse_anchor_hhmm(hhmm_local)
    candidate = (
        pendulum.instance(cycle_start)
        .in_timezone(LOCAL_TZ)
        .replace(hour=hour, minute=minute, second=0, microsecond=0)
    )
    if candidate < cycle_start:
        candidate = candidate.add(days=1)
    return candidate.in_timezone("UTC")


def _is_sla_entry(entry: dict) -> bool:
    return entry.get("kind") in (_KIND_MISSING_RUN, _KIND_DEADLINE_MISS) or str(
        entry.get("run_id") or ""
    ).startswith((_SLA_RUN_ID_PREFIX, _DEADLINE_RUN_ID_PREFIX))


def _matches_exclude_prefix(dag_id: str, prefix: str) -> bool:
    if not prefix:
        return False
    if dag_id.startswith(prefix):
        return True
    return any(part.startswith(prefix) for part in dag_id.split("."))


def _alert_exclude_prefixes(config: dict | None) -> list[str]:
    prefixes = (config or {}).get("alert_exclude_dag_prefixes")
    if prefixes is None:
        prefixes = _DEFAULT_CONFIG.get("alert_exclude_dag_prefixes") or []
    return list(prefixes)


def _is_alert_excluded_dag(dag_id: str, config: dict | None = None) -> bool:
    """True when this DAG must not open or update a Chat/Jira alert thread."""
    for prefix in _alert_exclude_prefixes(config):
        if _matches_exclude_prefix(dag_id, prefix):
            return True
    return False


def _is_sla_candidate(dag_id: str, schedule_interval, config: dict) -> bool:
    """True when a DAG row is eligible for the missing-run guard."""
    if _is_alert_excluded_dag(dag_id, config):
        return False
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


def _succeeded_this_cycle(
    history_rows: Iterable,
    *,
    hhmm: str,
    cycle_key: str,
    emitted: Iterable | None = None,
) -> set:
    """DAG ids that delivered in the current cycle.

    A successful automatic run counts, and so does any DAG that emitted a dataset
    event this cycle — the latter picks up an operator's
    ``run_type=impact_downstream_dependents`` recovery run, which ``_REAL_RUN_FILTER_DR``
    deliberately excludes from history but which really did unblock its dependents.
    """
    succeeded = {
        row.dag_id
        for row in history_rows
        if getattr(row, "state", None) == "success"
        and getattr(row, "start_date", None) is not None
        and _cycle_anchor(row.start_date, hhmm=hhmm).isoformat() == cycle_key
    }
    if emitted:
        succeeded |= set(emitted)
    return succeeded


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


def _union_indexes(*indexes) -> dict | None:
    """Union ``dag_id → {dag_ids}`` graphs, skipping sources that failed (``None``).

    Returns ``None`` only when *every* source failed, preserving the fail-closed
    contract callers rely on. A source that loaded but is empty still counts as
    available, so an empty dependencies.yaml yields ``{}`` rather than ``None``.
    """
    available = [index for index in indexes if index is not None]
    if not available:
        return None
    merged: dict = {}
    for index in available:
        for key, values in index.items():
            if values:
                merged.setdefault(key, set()).update(values)
    return merged


def _is_reprocessing_uri(uri: str) -> bool:
    """Whether a URI is the ``:reprocessing`` twin rather than a required dataset.

    The twin is the dependency string with the variant appended, and the dependency may
    itself carry a variant, so both ``<dag_id>:<task_id>:reprocessing`` and
    ``<dag_id>:<task_id>:first-run-of-day:reprocessing`` are twins. Requiring two
    separators keeps a task legitimately named ``reprocessing`` (``<dag_id>:
    reprocessing``, which no declared dependency currently uses) out of the match.
    """
    return uri.count(":") >= 2 and uri.endswith(_REPROCESSING_URI_SUFFIX)


def _producer_from_uri(uri: str) -> str | None:
    """Producer ``dag_id`` encoded in a Bietlejuice dataset URI.

    Only used to fill the gap left by ``task_outlet_dataset_reference``, which carries
    no row for dynamically published outlets. Everything after the first separator is
    opaque here — it may be ``<task_id>``, ``<task_id>:first-run-of-day``, or either of
    those with the reprocessing variant appended — so only the prefix is read, and every
    dependency declared in ``dependencies.yaml`` resolves to a ``bietlejuice.*`` or
    ``quintoml.*`` dag_id. A scheme-bearing URI such as ``s3://bucket/key`` is not one of
    ours and must not yield ``s3`` as a producer.
    """
    if "://" in uri:
        return None
    dag_id, _, remainder = uri.partition(":")
    if not remainder:
        return None
    return dag_id.strip() or None


def _required_datasets(datasets: dict | None) -> dict:
    """The datasets a normal cycle must satisfy — everything but the reprocessing branch.

    See ``_REPROCESSING_URI_SUFFIX``: the reprocessing twins belong to an OR branch that
    only fires during a reprocessing run, so they are neither required nor missing.
    """
    if not datasets:
        return {}
    return {
        uri: meta for uri, meta in datasets.items() if not _is_reprocessing_uri(uri)
    }


def _dataset_blocked(
    datasets: dict | None,
    *,
    emitted_uris: set | None,
    completed_dags: set,
) -> bool | None:
    """Whether a late dataset-scheduled DAG is genuinely still waiting on an upstream.

    ``True`` only when *every* dataset it is missing belongs to an upstream that has not
    finished with it — the DAG will start on its own and must stay quiet. ``False`` when
    it is ready, or when any missing dataset is already settled (``_dataset_settled``),
    which means it is stuck and has to be reported.

    That distinction is the whole point. Suppressing on "not every dataset satisfied"
    also silences the dropped-event case, which is the failure this guard exists to
    catch: a DAG sitting at 13/14 fails a plain readiness test, so the guard went to
    zero roots on every tick while dozens of DAGs stayed late.

    ``None`` means "no opinion" — a cron DAG with no dataset schedule, or one whose
    trigger state could not be read — so callers fall back to DAG-level reasoning
    instead of treating absence of evidence as evidence of blockage.
    """
    required = _required_datasets(datasets)
    if not required:
        return None
    missing = [uri for uri, meta in required.items() if not meta["satisfied"]]
    if not missing:
        return False
    return not any(
        _dataset_settled(
            uri,
            required[uri]["producers"],
            emitted_uris=emitted_uris,
            completed_dags=completed_dags,
        )
        for uri in missing
    )


def _log_dataset_graph_coverage(upstream_index: dict | None) -> None:
    """Report live-graph size so an inert graph is visible instead of silently empty.

    An empty graph reads exactly like a healthy one everywhere else — suppression just
    stops working — so the count is logged every cycle rather than inferred after the
    fact from alerts that never mention a producer.
    """
    if upstream_index is None:
        return
    edges = sum(len(producers) for producers in upstream_index.values())
    print(
        f"🔗 Live dataset graph: {edges} edge(s) over "
        f"{len(upstream_index)} dependent DAG(s)."
    )


def _log_dataset_status_coverage(status: dict) -> None:
    """Report how many datasets resolved a producer, per source.

    ``task_outlet_dataset_reference`` is empty for dynamically published outlets, which
    left every missing dataset unattributed and silently disabled the dropped-event
    verdict. Logging the split makes that visible and shows what the URI fallback
    recovers.
    """
    total = sum(len(datasets) for datasets in status.values())
    if not total:
        return
    attributed = sum(
        1
        for datasets in status.values()
        for meta in datasets.values()
        if meta["producers"]
    )
    print(
        f"🔗 Dataset trigger state: {len(status)} DAG(s), {total} dataset(s), "
        f"{total - attributed} without a producer."
    )


def _build_dataset_indexes(rows) -> tuple:
    """``(upstream_index, downstream_index)`` from live dataset-reference rows."""
    if rows is None:
        return None, None
    upstream: dict = {}
    downstream: dict = {}
    for row in rows:
        dependent = getattr(row, "dependent_dag_id", None)
        if not dependent:
            continue
        uri = getattr(row, "uri", None)
        producers = {
            getattr(row, "upstream_dag_id", None),
            _producer_from_uri(uri) if uri else None,
        }
        for producer in producers:
            if not producer or dependent == producer:
                continue
            upstream.setdefault(dependent, set()).add(producer)
            downstream.setdefault(producer, set()).add(dependent)
    return upstream, downstream


def _build_dataset_status(rows) -> dict:
    """``dag_id → {uri: {"satisfied": bool, "producers": set}}`` from query rows."""
    status: dict = {}
    for row in rows:
        dag_id = getattr(row, "dag_id", None)
        uri = getattr(row, "uri", None)
        if not dag_id or not uri:
            continue
        per_dag = status.setdefault(dag_id, {})
        entry = per_dag.setdefault(uri, {"satisfied": False, "producers": set()})
        if getattr(row, "satisfied", 0):
            entry["satisfied"] = True
        for producer in (
            getattr(row, "producer_dag_id", None),
            _producer_from_uri(uri),
        ):
            if producer and producer != dag_id:
                entry["producers"].add(producer)
    return status


def _dataset_settled(
    uri: str,
    producers: set,
    *,
    emitted_uris: set | None,
    completed_dags: set,
) -> bool:
    """Whether waiting on a missing dataset is pointless — the upstream is done with it.

    Two independent proofs, either of which means the DAG is stuck rather than pending:

    * the dataset's own event fired this cycle, yet this DAG has no queue row for it —
      Airflow dropped the update against a stale ``SerializedDagModel`` and never
      retro-applies it (2026-07-14 postmortem, ``enrich_chatbot`` at 13/14 forever);
    * the producing DAG finished a successful run this cycle and the dataset still never
      arrived.

    Completion is measured from real runs only and never from emissions. A producer that
    has emitted one early outlet is still mid-flight, and counting that as delivered is
    what promoted a whole downstream wavefront into alerts on 2026-07-25. The URI check
    covers the case run history cannot see: an operator's
    ``run_type=impact_downstream_dependents`` recovery run is excluded from history by
    ``_REAL_RUN_FILTER_DR`` but does emit real events.

    ``emitted_uris`` of ``None`` means the event table could not be read, so only the
    completion proof applies.
    """
    if emitted_uris is not None and uri in emitted_uris:
        return True
    return bool(producers & completed_dags)


def _classify_dataset_state(
    datasets: dict | None,
    *,
    emitted_uris: set | None,
    completed_dags: set,
) -> dict:
    """Explain why a late dataset-scheduled DAG still has no run.

    A dataset counts as *ready but unrecorded* when it is missing but its upstream is
    already finished with it — see ``_dataset_settled``, which is the same test the root
    gate applies, so the verdict in the message and the decision to send it can never
    disagree.

    Only the required branch is counted (see ``_required_datasets``), so the quotient
    reflects what actually gates the next run rather than every URI the flattened
    schedule reference happens to list.

    Returns ``{}`` for DAGs with no dataset schedule (cron), so callers can leave the
    message untouched.
    """
    required_datasets = _required_datasets(datasets)
    if not required_datasets:
        return {}
    required = len(required_datasets)
    missing = sorted(
        uri for uri, meta in required_datasets.items() if not meta["satisfied"]
    )
    ready, blocking = [], set()
    for uri in missing:
        if _dataset_settled(
            uri,
            required_datasets[uri]["producers"],
            emitted_uris=emitted_uris,
            completed_dags=completed_dags,
        ):
            ready.append(uri)
        else:
            blocking.update(required_datasets[uri]["producers"])
    return {
        "dataset_required": required,
        "dataset_satisfied": required - len(missing),
        "dataset_missing": missing,
        "dataset_ready_missing": ready,
        "dataset_blocking_dags": sorted(blocking),
        "dataset_verdict": (
            _VERDICT_DROPPED_EVENT
            if not missing or ready
            else _VERDICT_WAITING_UPSTREAM
        ),
    }


def _enrich_findings_with_dataset_state(
    findings: list,
    dataset_status: dict | None,
    *,
    emitted_uris: set | None,
    completed_dags: set,
) -> None:
    """Attach dataset counts, missing URIs and the verdict to each finding in place."""
    if not findings or not dataset_status:
        return
    for finding in findings:
        finding.update(
            _classify_dataset_state(
                dataset_status.get(finding["dag_id"]),
                emitted_uris=emitted_uris,
                completed_dags=completed_dags,
            )
        )


def _load_upstream_index_safe(
    dataset_upstream_index: dict | None = None,
) -> dict | None:
    """Upstream index from ``dependencies.yaml``, unioned with the live dataset graph.

    Returns ``None`` only when both sources are unavailable, so SLA detection can fail
    closed (skip opening new missing-run alerts) instead of treating every late DAG as
    a root with an empty upstream map. A successfully loaded empty file still returns
    ``{}``.
    """
    yaml_index = None
    try:
        deps = BietlejuiceDependencyHelper.read_dependencies()
        if isinstance(deps, dict):
            yaml_index = _build_upstream_index(deps)
        else:
            print("⚠️  dependencies.yaml did not parse to a mapping; ignoring it.")
    except Exception as exc:  # noqa: BLE001 — operational guard
        print(f"⚠️  Failed to load/index dependencies.yaml for SLA upstreams: {exc}")
    return _union_indexes(yaml_index, dataset_upstream_index)


def _select_sla_roots(
    late_dag_ids: set,
    *,
    upstream_index: dict,
    succeeded_this_cycle: set,
    expected_this_cycle: set | None = None,
    dataset_status: dict | None = None,
    emitted_uris: set | None = None,
    completed_dags: set | None = None,
) -> tuple[list, int, bool]:
    """Return (root dag_ids sorted, suppressed_count, used_fallback).

    A *confirmed* root is a late DAG that is not blocked on a dataset, where no upstream
    is itself late and every upstream expected to run this cycle already succeeded.
    Upstreams outside ``expected_this_cycle`` (paused, inactive, or excluded from the
    guard) cannot be waited on, so they never block — otherwise their dependents would
    be permanently unalertable.

    Blockage is judged per dataset, not per DAG, because that is how Airflow gates a
    run. ``succeeded_this_cycle`` counts a producer as delivered the moment it emits
    *any* outlet, so a mid-flight upstream would otherwise promote its whole downstream
    wavefront into "confirmed" roots that start on their own minutes later — the
    2026-07-25 cascade, where dw_accounts_receivable alerted while still short the one
    dataset its upstream was computing. ``_dataset_blocked`` draws the line at whether
    the upstream is *finished* with the specific dataset, so a DAG stuck on a dropped
    event is still reported while one waiting on live work is not.

    When nothing is confirmed but unblocked DAGs *are* late, fall back to the
    topological tops of the late set (no upstream is itself late) and flag it. Reporting
    a lower-confidence root beats going silent on a real cascade, which is the failure
    mode the 2026-07-14 postmortem describes. The fallback still excludes DAGs we
    positively know are blocked: that is evidence, not absence of it. When the trigger
    state could not be read at all, ``_dataset_blocked`` returns ``None`` and every late
    DAG stays eligible, preserving the fail-open behaviour.
    """
    status = dataset_status or {}
    completed = completed_dags or set()
    tops = [
        dag_id
        for dag_id in sorted(late_dag_ids)
        if _dataset_blocked(
            status.get(dag_id),
            emitted_uris=emitted_uris,
            completed_dags=completed,
        )
        is not True
        and not any(
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


def _apply_missing_run_cap(findings: list, config: dict) -> list:
    """Bound how many missing-run roots one tick may report.

    The readiness gate keeps a recovering cascade quiet on its own, so this only bites
    when the dataset trigger state could not be read and root selection fell back to
    the topological tops of the late set. The latest roots are kept, since a cap that
    truncated alphabetically would drop the worst offenders as readily as the mildest.
    Survivors carry ``capped_count`` so the alert says what was withheld.
    """
    cap = int(config.get("sla_max_missing_run_alerts", 0) or 0)
    if cap <= 0 or len(findings) <= cap:
        return findings
    kept = sorted(findings, key=lambda f: f.get("late_by_s", 0), reverse=True)[:cap]
    dropped = len(findings) - len(kept)
    print(
        f"⏰ SLA missing-run: alert cap {cap} reached; "
        f"{dropped} root(s) late but not reported."
    )
    for finding in kept:
        finding["capped_count"] = dropped
    return kept


def _evaluate_sla_missing_runs(
    candidate_dag_ids: list,
    history_rows: list,
    *,
    now: datetime,
    config: dict,
    upstream_index: dict,
    downstream_index: dict | None,
    expected_dag_ids: set | None = None,
    emitted_this_cycle: Iterable | None = None,
    emitted_uris: set | None = None,
    fetch_dataset_status=None,
) -> list:
    """Build ``missing_run`` findings for late roots past their due_at.

    ``candidate_dag_ids`` are the DAGs evaluated for lateness; ``expected_dag_ids``
    is the full eligible universe used to decide which upstreams can be waited on.
    They differ only under the ``only_dags`` debug filter, where narrowing the
    evaluation must not make active upstreams look unexpected.

    ``emitted_this_cycle`` are DAGs that published a dataset event this cycle. They
    count as started (so an operator's recovery run closes the alert instead of
    re-firing every 30 minutes) and as succeeded (so their dependents can still be
    confirmed as roots), neither of which ``_REAL_RUN_FILTER_DR`` can see.

    ``emitted_uris`` are the dataset URIs whose event fired this cycle, at dataset
    granularity rather than the DAG granularity of ``emitted_this_cycle``. Only the URI
    tells a dropped event apart from an upstream that has not reached that outlet yet,
    since producers emit progressively.

    ``fetch_dataset_status`` is called once with the late dag_ids and returns their
    dataset trigger state (or ``None`` when unreadable). It is a callable rather than
    a value because the late set is only known here, and scoping the query to it keeps
    the read small; the same result gates root selection and enriches the messages, so
    the state is read once per cycle.

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

    emitted = set(emitted_this_cycle or ())
    # Two sets, deliberately: completed_this_cycle is real runs that finished, and is
    # what proves an upstream is done with a dataset. succeeded_this_cycle adds the
    # emitters on top for root confirmation, where a recovery run does count as
    # delivery. Conflating them is what caused the 2026-07-25 avalanche.
    completed_this_cycle = _succeeded_this_cycle(
        history_rows, hhmm=hhmm, cycle_key=cycle_key
    )
    succeeded_this_cycle = completed_this_cycle | emitted
    started_this_cycle = {
        dag_id for dag_id, cycles in first_starts.items() if cycle_key in cycles
    } | emitted

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
    dataset_status = (
        fetch_dataset_status(sorted(late_ids)) if fetch_dataset_status else None
    )
    roots, suppressed_count, used_fallback = _select_sla_roots(
        late_ids,
        upstream_index=upstream_index,
        dataset_status=dataset_status,
        emitted_uris=emitted_uris,
        completed_dags=completed_this_cycle,
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
    findings = _apply_missing_run_cap(findings, config)
    _enrich_findings_with_dataset_state(
        findings,
        dataset_status,
        emitted_uris=emitted_uris,
        completed_dags=completed_this_cycle,
    )
    return findings


def _evaluate_deadline_misses(
    deadline_by_dag: dict,
    history_rows: list,
    *,
    now: datetime,
    cycle_start: datetime,
    hhmm: str,
    emitted: Iterable | None = None,
) -> list:
    succeeded = _succeeded_this_cycle(
        history_rows, hhmm=hhmm, cycle_key=cycle_start.isoformat(), emitted=emitted
    )
    findings = []
    for dag_id, hhmm_local in deadline_by_dag.items():
        due_at = _deadline_at(cycle_start, hhmm_local)
        if now <= due_at or dag_id in succeeded:
            continue
        late_by_s = (now - due_at).total_seconds()
        findings.append(
            {
                "kind": _KIND_DEADLINE_MISS,
                "dag_id": dag_id,
                "run_id": _deadline_run_id(cycle_start),
                "tier": "standard",
                "cycle_anchor": cycle_start.isoformat(),
                "due_at": due_at.isoformat(),
                "deadline_localtime": hhmm_local,
                "late_by_s": late_by_s,
                "elapsed_s": late_by_s,
            }
        )
    print(
        f"⏰ SLA deadline: {len(deadline_by_dag)} candidate(s), {len(findings)} missed."
    )
    return findings


def _build_alert_text(finding: dict) -> str:
    """JiraOps / log description — dispatches by finding kind."""
    if finding.get("kind") == _KIND_DEADLINE_MISS:
        return _deadline_initial_text(
            _entry_from_finding(finding), finding.get("late_by_s", 0)
        )
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
        "criticality": finding.get("criticality"),
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
                "capped_count": finding.get("capped_count", 0),
                "root_is_fallback": bool(finding.get("root_is_fallback")),
                "dataset_required": finding.get("dataset_required"),
                "dataset_satisfied": finding.get("dataset_satisfied"),
                "dataset_missing": list(finding.get("dataset_missing") or []),
                "dataset_ready_missing": list(
                    finding.get("dataset_ready_missing") or []
                ),
                "dataset_blocking_dags": list(
                    finding.get("dataset_blocking_dags") or []
                ),
                "dataset_verdict": finding.get("dataset_verdict"),
            }
        )
    elif kind == _KIND_DEADLINE_MISS:
        entry.update(
            {
                "cycle_anchor": finding.get("cycle_anchor"),
                "due_at": finding.get("due_at"),
                "deadline_localtime": finding.get("deadline_localtime"),
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


def _join_capped(items: list, limit: int) -> str:
    """``"a, b … and N more"`` — comma list capped at ``limit`` with an overflow tail."""
    shown = list(items)[:limit]
    overflow = len(items) - len(shown)
    suffix = f" … and {overflow} more" if overflow > 0 else ""
    return f"{', '.join(shown)}{suffix}"


def _short_dag_label(dag_id: str) -> str:
    """Strip ``bietlejuice.`` for Chat display; leave other namespaces intact."""
    if isinstance(dag_id, str) and dag_id.startswith(_BIETLEJUICE_DAG_PREFIX):
        return dag_id[len(_BIETLEJUICE_DAG_PREFIX) :]
    return dag_id


def _format_impacted_dw_line(
    impacted_dw_dags: list | None, *, limit: int = _IMPACTED_DW_LIST_LIMIT
) -> str:
    """Render the DW blast-radius bullet for Chat / JiraOps (truncated after ``limit``)."""
    dags = list(impacted_dw_dags or [])
    if not dags:
        return "• Impacted DW: none"
    labels = [_short_dag_label(dag_id) for dag_id in dags]
    return f"• Impacted DW ({len(dags)}): {_join_capped(labels, limit)}"


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


def _format_local_hhmm(value) -> str:
    """Render a datetime / ISO string as ``HH:MM`` São Paulo wall clock."""
    dt = _parse_iso_datetime(value)
    if dt is None:
        return "unknown"
    return pendulum.instance(dt).in_timezone(LOCAL_TZ).format("HH:mm") + " (São Paulo)"


def _dataset_state_lines(entry: dict) -> list:
    """Dataset-trigger bullets: how many conditions are met, and what that implies.

    Empty for cron DAGs (no dataset schedule), which keeps their message as before.
    """
    required = entry.get("dataset_required")
    if not required:
        return []
    satisfied = entry.get("dataset_satisfied") or 0
    missing = list(entry.get("dataset_missing") or [])
    verdict = entry.get("dataset_verdict")
    counts = f"• Datasets: {satisfied}/{required} satisfied"
    lines = [
        f"{counts} — missing {_join_capped(missing, _MISSING_DATASET_LIST_LIMIT)}"
        if missing
        else counts
    ]
    if verdict == _VERDICT_DROPPED_EVENT:
        cause = (
            "producer already delivered, update never recorded"
            if entry.get("dataset_ready_missing")
            else "all conditions met, no run created"
        )
        lines.append(f"• Likely a dropped dataset event ({cause})")
    elif verdict == _VERDICT_WAITING_UPSTREAM:
        blocking = list(entry.get("dataset_blocking_dags") or [])
        if blocking:
            lines.append(
                f"• Waiting on: {_join_capped(blocking, _MISSING_DATASET_LIST_LIMIT)}"
            )
    return lines


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
        lines.append(
            f"• Late by: {_format_duration(late_by_s)} "
            f"(due {_format_utc_hhmm(entry.get('due_at'))})"
        )
        lines.extend(_dataset_state_lines(entry))
        dw_line = _format_impacted_dw_line(entry.get("impacted_dw_dags") or [])
        also_waiting = entry.get("also_waiting_count") or 0
        if also_waiting:
            dw_line = f"{dw_line} · also waiting: {also_waiting}"
        lines.append(dw_line)
    else:
        lines.append(f"• Late by: {_format_duration(late_by_s)}")
        also_waiting = entry.get("also_waiting_count")
        if isinstance(also_waiting, int) and also_waiting > 0:
            lines.append(f"• Also waiting downstream: {also_waiting} DAG(s)")
    if footer:
        lines.append(footer)
    return "\n".join(lines)


def _initial_text(entry: dict, elapsed_s: float) -> str:
    if entry.get("kind") == _KIND_DEADLINE_MISS:
        return _deadline_initial_text(entry, elapsed_s)
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
    )


def _update_text(
    entry: dict, elapsed_s: float, *, impacted_dw_count: int | None = None
) -> str:
    if entry.get("kind") == _KIND_DEADLINE_MISS:
        return _deadline_update_text(entry, elapsed_s)
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


def _deadline_initial_text(entry: dict, late_by_s: float) -> str:
    return (
        f"⏰ *{entry['dag_id']}* not finished by its "
        f"{entry['deadline_localtime']} São Paulo deadline\n"
        f"• Owner: {_owner_label(entry)}\n"
        f"• Late by: {_format_duration(late_by_s)}"
    )


def _deadline_update_text(entry: dict, late_by_s: float) -> str:
    return (
        f"⏰ *{entry['dag_id']}* still not finished — "
        f"{_format_duration(late_by_s)} past its "
        f"{entry['deadline_localtime']} São Paulo deadline"
    )


def _deadline_finished_text(
    entry: dict, finished_at: datetime, late_by_s: float
) -> str:
    return (
        f"✅ *{entry['dag_id']}* finished at {_format_local_hhmm(finished_at)}, "
        f"{_format_duration(late_by_s)} after its "
        f"{entry['deadline_localtime']} São Paulo deadline."
    )


def _load_downstream_index_safe(
    dataset_downstream_index: dict | None = None,
) -> dict | None:
    """Downstream index from dependencies.yaml, unioned with the live dataset graph.

    Never fail the monitor cycle on read/parse errors or invalid upstream shapes
    (e.g. ``{}`` / dicts without ``any``/``all``), which raise ``ValueError`` inside
    ``find_unique_dependencies_in_dependency_object``.

    Returns ``None`` only when both sources are unavailable, so follow-ups can keep the
    ledger snapshot instead of treating a load failure as ``Impacted DW DAGs: none``.
    A successfully loaded empty file still returns ``{}``.

    Adding the live edges makes DW blast radius *larger* than dependencies.yaml alone:
    paths that hop through a namespace missing from the YAML (``bietlejuice.x →
    quintoml.y → bietlejuice.dw_z``) resolve here for the first time.
    """
    yaml_index = None
    try:
        deps = BietlejuiceDependencyHelper.read_dependencies()
        if isinstance(deps, dict):
            yaml_index = BietlejuiceDependencyHelper.build_downstream_index(deps)
        else:
            print("⚠️  dependencies.yaml did not parse to a mapping; ignoring it.")
    except Exception as exc:  # noqa: BLE001 — operational guard; keep alerting alive
        print(f"⚠️  Failed to load/index dependencies.yaml for DW impact: {exc}")
    return _union_indexes(yaml_index, dataset_downstream_index)


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

    * Empty ``critical_dags`` → all ``standard`` (Chat only).
    * ``slow`` → ``critical`` when the DAG is in the set or transitively blocks one.
    * ``missing_run`` and ``deadline_miss`` → ``critical`` on **membership only**.
      The transitive expansion the slow tier uses would page on the chronically-late
      upstream layer (~28 DAGs late on 13-15 of 14 days) every night, so a late
      upstream stays Chat-only.
    """
    critical = set(critical_dags or ())
    for finding in findings:
        if finding.get("kind") in (_KIND_MISSING_RUN, _KIND_DEADLINE_MISS):
            finding["tier"] = (
                "critical" if finding["dag_id"] in critical else "standard"
            )
        elif _impacts_critical(finding["dag_id"], critical, downstream_index):
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
    kind = finding.get("kind")
    is_missing_run = kind == _KIND_MISSING_RUN
    is_deadline_miss = kind == _KIND_DEADLINE_MISS
    if is_deadline_miss:
        kind_tag = "sla deadline miss"
    elif is_missing_run:
        kind_tag = "sla missing run"
    else:
        kind_tag = "runtime anomaly"
    tags = [dag_id, kind_tag, "critical"]
    if test:
        tags.append("test")
    try:
        # Title/description must stay inside try: a bad finding must not abort the
        # whole monitor_dag_runtimes task — log and skip this page instead.
        if is_deadline_miss:
            headline = "DAG missed SLA deadline"
        elif is_missing_run:
            headline = "DAG missed SLA start"
        else:
            headline = "DAG runtime anomaly"
        title = _truncate_text(
            f"{'[TEST] ' if test else ''}{headline}: {dag_id}",
            _JIRA_MESSAGE_MAX,
        )
        description = _truncate_text(_build_alert_text(finding), _JIRA_DESCRIPTION_MAX)
        extra_properties = {
            "DAG": dag_id,
            "RunId": run_id,
            "DAGOwner": _owner_label(finding),
        }
        if is_deadline_miss:
            extra_properties["DeadlineLocalTime"] = finding["deadline_localtime"]
            extra_properties["LateBy"] = _format_duration(finding.get("late_by_s") or 0)
        elif is_missing_run:
            extra_properties["DueAt"] = finding.get("due_at")
            extra_properties["LateBy"] = _format_duration(finding.get("late_by_s") or 0)
        else:
            extra_properties["PctOverBaseline"] = finding.get("pct_over")
        level = finding.get("criticality")
        priority = CriticalityEnum.to_opsgenie_priority(level or CriticalityEnum.HIGH)
        if level:
            extra_properties["Criticality"] = level
        creds = json.loads(Variable.get(JIRA_OPS_VARIABLE))
        client = JiraOpsClient(creds)
        response = client.create_alert(
            message=title,
            description=description,
            tags=tags,
            extra_properties=extra_properties,
            responder_team_id=responder_team_id,
            alias=f"dag-runtime-{dag_id}-{run_id}",
            priority=priority,
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


def _fetch_declared_criticality(session) -> tuple[dict, dict]:
    """(criticality_by_dag, deadline_by_dag) from DAG tags.

    criticality is the highest of the declared ``criticality:`` tag and the
    ``effective_tier:`` tag. A ``sla_deadline_localtime:`` tag is overridden with
    the resolved tier's default deadline only when that tier differs from the
    declared DAG tier. A DAG with no deadline tag stays out of deadline alerting;
    the tier alone never invents a deadline.
    """
    rows = session.execute(
        _DAG_TAGS_QUERY,
        {
            "criticality_prefix": f"{CRITICALITY_TAG_PREFIX}%",
            "deadline_prefix": f"{SLA_DEADLINE_TAG_PREFIX}%",
            "effective_prefix": f"{EFFECTIVE_TIER_TAG_PREFIX}%",
        },
    ).fetchall()
    criticality_by_dag = {}
    deadline_by_dag = {}
    effective_by_dag = {}
    valid_criticalities = set(CriticalityEnum.get_available_enum_values())
    for row in rows:
        if isinstance(row, (tuple, list)):
            dag_id, name = row[0], row[1]
        else:
            dag_id = getattr(row, "dag_id", row[0])
            name = getattr(row, "name", row[1])
        if name.startswith(CRITICALITY_TAG_PREFIX):
            val = name[len(CRITICALITY_TAG_PREFIX) :]
            if val in valid_criticalities:
                criticality_by_dag[dag_id] = val
            else:
                print(f"⚠️  Ignoring malformed tag {name!r} on {dag_id}")
        elif name.startswith(EFFECTIVE_TIER_TAG_PREFIX):
            val = name[len(EFFECTIVE_TIER_TAG_PREFIX) :]
            if val in valid_criticalities:
                effective_by_dag[dag_id] = val
            else:
                print(f"⚠️  Ignoring malformed tag {name!r} on {dag_id}")
        elif name.startswith(SLA_DEADLINE_TAG_PREFIX):
            val = name[len(SLA_DEADLINE_TAG_PREFIX) :]
            try:
                _parse_anchor_hhmm(val)
                deadline_by_dag[dag_id] = val
            except (TypeError, ValueError):
                print(f"⚠️  Ignoring malformed tag {name!r} on {dag_id}")
    for dag_id in set(criticality_by_dag) | set(effective_by_dag):
        declared = criticality_by_dag.get(dag_id)
        resolved = CriticalityEnum.highest([declared, effective_by_dag.get(dag_id)])
        criticality_by_dag[dag_id] = resolved
        if dag_id in deadline_by_dag and resolved != declared:
            deadline_by_dag[dag_id] = CriticalityEnum.default_deadline(resolved)
    return criticality_by_dag, deadline_by_dag


def _attach_criticality(findings: list, criticality_by_dag: dict) -> None:
    for finding in findings:
        finding["criticality"] = criticality_by_dag.get(finding["dag_id"])


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


def _fetch_sla_succeeded(session, dag_ids: list, cycle_start: datetime) -> dict:
    if not dag_ids:
        return {}
    rows = session.execute(
        _SLA_SUCCEEDED_QUERY,
        {"dag_ids": list(dag_ids), "cycle_start": cycle_start},
    ).fetchall()
    return {row.dag_id: row.first_success for row in rows}


def _fetch_dataset_edges(session):
    """Live dataset-scheduling edges, or ``None`` when they cannot be read."""
    try:
        return session.execute(_DATASET_EDGES_QUERY).fetchall()
    except Exception as exc:  # noqa: BLE001 — operational guard; fall back to YAML
        print(f"⚠️  Failed to read live dataset references: {exc}")
        return None


def _fetch_dataset_satisfaction(session, dag_ids: list) -> dict | None:
    """Map ``dag_id → {uri: {...}}`` for the given DAGs, or ``None`` on failure."""
    if not dag_ids:
        return {}
    try:
        rows = session.execute(
            _DATASET_SATISFACTION_QUERY, {"dag_ids": list(dag_ids)}
        ).fetchall()
    except Exception as exc:  # noqa: BLE001 — diagnostics only; never fail the alert
        print(f"⚠️  Failed to read dataset trigger state: {exc}")
        return None
    status = _build_dataset_status(rows)
    _log_dataset_status_coverage(status)
    return status


def _fetch_emitted_dataset_uris(session, cycle_start: datetime) -> set | None:
    """Dataset URIs whose event fired this cycle, or ``None`` when unreadable.

    ``None`` is distinct from the empty set: no events at all means nothing has been
    produced, whereas a failed read means the dropped-event proof is simply unavailable
    and callers must not treat its absence as evidence.
    """
    try:
        rows = session.execute(
            _SLA_EMITTED_URIS_QUERY, {"cycle_start": cycle_start}
        ).fetchall()
    except Exception as exc:  # noqa: BLE001 — degrade to run-completion evidence only
        print(f"⚠️  Failed to read dataset events for this cycle: {exc}")
        return None
    return {row.uri for row in rows if getattr(row, "uri", None)}


def _fetch_sla_emitted(session, cycle_start: datetime) -> dict:
    """Map ``dag_id → first dataset-event timestamp`` published in the current cycle."""
    try:
        rows = session.execute(
            _SLA_EMITTED_QUERY, {"cycle_start": cycle_start}
        ).fetchall()
    except Exception as exc:  # noqa: BLE001 — degrade to run-based detection only
        print(f"⚠️  Failed to read dataset emissions for this cycle: {exc}")
        return {}
    return {row.dag_id: row.first_emit for row in rows}


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
            # Mirrors the postmortem shape (13/14) so simulate exercises the
            # dropped-event bullets and the recovery trigger link.
            "dataset_required": 14,
            "dataset_satisfied": 13,
            "dataset_missing": ["internal_chat:simulated-dataset:first-run-of-day"],
            "dataset_ready_missing": [
                "internal_chat:simulated-dataset:first-run-of-day"
            ],
            "dataset_blocking_dags": [],
            "dataset_verdict": _VERDICT_DROPPED_EVENT,
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
        if str(run_id).startswith(_DEADLINE_RUN_ID_PREFIX):
            default_kind = _KIND_DEADLINE_MISS
        elif str(run_id).startswith(_SLA_RUN_ID_PREFIX):
            default_kind = _KIND_MISSING_RUN
        else:
            default_kind = _KIND_SLOW
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
    criticality_by_dag, deadline_by_dag = _fetch_declared_criticality(session)
    if opts["critical_dags"] is not None:
        config["critical_dags"] = opts["critical_dags"]
    else:
        config["critical_dags"] = sorted(
            dag_id
            for dag_id, level in criticality_by_dag.items()
            if level in CriticalityEnum.PAGING
        )
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

    # One read of the live dataset graph per cycle, feeding both index directions.
    dataset_upstream_index, dataset_downstream_index = _build_dataset_indexes(
        _fetch_dataset_edges(session)
    )
    _log_dataset_graph_coverage(dataset_upstream_index)
    downstream_index = _load_downstream_index_safe(dataset_downstream_index)

    # --- Simulate: fabricate findings and post a chosen lifecycle phase (no DB / ledger).
    # simulate_state drives which message to emit for the SAME synthetic thread, so a few
    # manual triggers walk the whole lifecycle: (unset)=initial → running → success/failed.
    # simulate_missing_runs switches the synthetic findings to the SLA missing-run shape.
    if opts["simulate"]:
        if opts["simulate_missing_runs"]:
            findings = _synthetic_missing_run_findings(config, opts["simulate_dags"])
            _enrich_findings_with_dw_impact(findings, downstream_index)
            _assign_alert_tiers(findings, config["critical_dags"], downstream_index)
            _attach_criticality(findings, criticality_by_dag)
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
                print(f"   • [missing_run/{f['tier']}] {_build_alert_text(f)}")
            if opts["dry_run"] or not deliver:
                print("ℹ️  Not delivering (simulate dry-run / gate). Logging only.")
                return
            if not state:
                for finding in findings:
                    _deliver_initial(finding, gchat_dest, jira_team, is_test, config)
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
        _attach_criticality(findings, criticality_by_dag)
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
                _deliver_initial(finding, gchat_dest, jira_team, is_test, config)
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

    # Resolved once per cycle: missing-run detection needs the eligible set, and
    # follow-up needs it to stop tracking DAGs that left it (paused/deactivated).
    sla_enabled = config.get("sla_enabled", True)
    sla_candidates = _fetch_sla_candidates(session, config) if sla_enabled else []
    sla_cycle_start = _cycle_anchor(
        now, hhmm=_resolve_anchor_hhmm(config.get("sla_cycle_anchor_local_time"))
    )
    # Shared by detection (a recovery run must not keep alerting) and follow-up
    # (it must close the thread), so it is read once.
    sla_emitted = _fetch_sla_emitted(session, sla_cycle_start) if sla_enabled else {}
    sla_emitted_uris = (
        _fetch_emitted_dataset_uris(session, sla_cycle_start) if sla_enabled else None
    )
    sla_findings = (
        _collect_sla_findings(
            session,
            config,
            now,
            downstream_index,
            candidates=sla_candidates,
            only_dags=opts["only_dags"],
            dataset_upstream_index=dataset_upstream_index,
            emitted=sla_emitted,
            emitted_uris=sla_emitted_uris,
        )
        if sla_enabled
        else []
    )
    deadline_candidates = {
        dag_id: hhmm
        for dag_id, hhmm in deadline_by_dag.items()
        if dag_id in set(sla_candidates)
    }
    if opts["only_dags"]:
        deadline_candidates = {
            d: h for d, h in deadline_candidates.items() if d in set(opts["only_dags"])
        }
    deadline_findings = (
        _evaluate_deadline_misses(
            deadline_candidates,
            _fetch_sla_history(session, list(deadline_candidates), sla_cycle_start),
            now=now,
            cycle_start=sla_cycle_start,
            hhmm=_resolve_anchor_hhmm(config.get("sla_cycle_anchor_local_time")),
            emitted=set(sla_emitted),
        )
        if sla_enabled and deadline_candidates
        else []
    )

    all_findings = findings + sla_findings + deadline_findings
    _assign_alert_tiers(all_findings, config["critical_dags"], downstream_index)
    _attach_criticality(all_findings, criticality_by_dag)
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
        print(f"   • [missing_run/{f['tier']}] {_build_alert_text(f)}")
    for f in deadline_findings:
        print(f"   • [deadline_miss/{f['tier']}] {_build_alert_text(f)}")
    print(
        f"⏱️ {len(findings)} anomalous run(s); "
        f"⏰ {len(sla_findings)} missing-run root(s); "
        f"⏰ {len(deadline_findings)} deadline miss(es); "
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
        sla_emitted=sla_emitted,
    )

    # 2) Open new incidents for anomalies not yet tracked (and not just closed above).
    for finding in all_findings:
        if _is_alert_excluded_dag(finding["dag_id"], config):
            continue
        key = _run_key(finding["dag_id"], finding["run_id"])
        if key in ledger or key in already_tracked:
            continue
        entry = _entry_from_finding(finding, first_alert_ts=now.isoformat())
        # Every anomaly goes to Chat (lifecycle). The critical tier also pages JiraOps —
        # slow DAGs in critical_dags or blocking one, missing-run DAGs in critical_dags.
        # Gate ledger on *all* required deliveries: if Chat succeeds but Jira fails,
        # do not track yet — otherwise later cycles skip the finding and on-call is
        # never paged despite _send_jira_alert's "retry next cycle" log.
        jira_ok = True
        if finding["tier"] == "critical":
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
    dataset_upstream_index: dict | None = None,
    emitted: dict | None = None,
    emitted_uris: set | None = None,
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
    upstream_index = _load_upstream_index_safe(dataset_upstream_index)
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
    emitted_ids = set(emitted or {})
    # Scoped to the late set rather than the reported roots: readiness has to be known
    # before a root can be chosen, and the same read then enriches the messages.
    return _evaluate_sla_missing_runs(
        candidates,
        history_rows,
        now=now,
        config=config,
        upstream_index=upstream_index,
        downstream_index=downstream_index,
        expected_dag_ids=eligible,
        emitted_this_cycle=emitted_ids,
        emitted_uris=emitted_uris,
        fetch_dataset_status=lambda dag_ids: _fetch_dataset_satisfaction(
            session, dag_ids
        ),
    )


def _deliver_initial(
    finding, gchat_dest, jira_team, is_test, config: dict | None = None
) -> None:
    """Send the initial alert for one finding (used by simulate mode).

    Chat always; JiraOps additionally for the critical tier (slow or missing-run).
    """
    if _is_alert_excluded_dag(finding["dag_id"], config):
        print(f"ℹ️  Skipping alert delivery for excluded DAG {finding['dag_id']}.")
        return
    if finding["tier"] == "critical":
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


def _drop_alert_excluded_entries(ledger: dict, config: dict) -> None:
    """Stop tracking excluded DAGs without posting close messages."""
    for key, entry in list(ledger.items()):
        if not _is_alert_excluded_dag(entry["dag_id"], config):
            continue
        print(f"ℹ️  Dropping tracking for excluded DAG {entry['dag_id']}.")
        del ledger[key]


def _follow_up_tracked_runs(
    session,
    ledger: dict,
    gchat_dest,
    now: datetime,
    downstream_index: dict | None,
    config: dict,
    *,
    sla_candidates: list | None = None,
    sla_emitted: dict | None = None,
) -> None:
    """Fetch the current state of tracked runs and apply follow-up messaging."""
    if not ledger:
        return
    _drop_alert_excluded_entries(ledger, config)
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
    cycle_anchor = _cycle_anchor(now, hhmm=hhmm)
    tracked_dag_ids = [e["dag_id"] for e in sla_entries]
    started = _fetch_sla_started(
        session,
        tracked_dag_ids,
        cycle_anchor,
    )
    # An operator's impact_downstream_dependents run is invisible to _SLA_STARTED_QUERY
    # (manual run types are filtered out), but its dataset emissions prove the chain
    # moved — without this the alert would keep repeating after the fix.
    for dag_id in tracked_dag_ids:
        first_emit = (sla_emitted or {}).get(dag_id)
        if first_emit is not None:
            started.setdefault(dag_id, first_emit)
    deadline_dag_ids = [
        e["dag_id"] for e in sla_entries if e.get("kind") == _KIND_DEADLINE_MISS
    ]
    succeeded = _fetch_sla_succeeded(session, deadline_dag_ids, cycle_anchor)
    for dag_id in deadline_dag_ids:
        first_emit = (sla_emitted or {}).get(dag_id)
        if first_emit is not None:
            succeeded.setdefault(dag_id, first_emit)
    _apply_sla_follow_up(
        ledger, started, gchat_dest, now, config, succeeded_by_dag=succeeded
    )


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
    succeeded_by_dag: dict | None = None,
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

        if entry.get("kind") == _KIND_DEADLINE_MISS:
            finished_at = (succeeded_by_dag or {}).get(entry["dag_id"])
            due_at = _parse_iso_datetime(entry.get("due_at"))
            if finished_at is not None:
                late_by_s = (
                    (finished_at - due_at).total_seconds()
                    if due_at is not None
                    else 0.0
                )
                if not _post_gchat(
                    gchat_dest,
                    _deadline_finished_text(entry, finished_at, late_by_s),
                    _thread_key(entry["dag_id"], entry["run_id"]),
                ):
                    continue
                del ledger[key]
                continue
            late_by_s = (now - due_at).total_seconds() if due_at is not None else 0.0
            _post_gchat(
                gchat_dest,
                _deadline_update_text(entry, late_by_s),
                _thread_key(entry["dag_id"], entry["run_id"]),
            )
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
        "Every anomaly goes to Google Chat (tracked to closure); slow DAGs declaring "
        "criticality Critical/High or that block them also page JiraOps on-caller; "
        "missing-run DAGs declaring criticality Critical/High page too."
    ),
    schedule="*/30 * * * *",
    catchup=False,
    tags=["monitoring", "platform", "runtime-anomaly", "sla"],
) as dag:
    PythonOperator(
        task_id="monitor_dag_runtimes",
        python_callable=monitor_dag_runtimes,
    )
