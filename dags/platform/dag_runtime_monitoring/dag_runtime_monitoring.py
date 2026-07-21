"""
airflow parsing enforcement

Note: this line above forces Airflow to parse this file for implemented DAGs.

Runtime-anomaly monitor. Every 30 minutes it inspects every currently-running DAG
run and flags any whose elapsed time is anomalous *relative to that same DAG's own
recent successful runs* (P<percentile> of durations over the last <lookback_days>,
times a factor, and only past an absolute min-duration floor) — no hardcoded per-DAG
time thresholds.

Alerting is tiered by ``critical_dags`` (soft-launch: empty list → Chat only):
  * Every over-baseline DAG is reported to Google Chat and **tracked to closure**
    (threaded updates while running, final message on success/failure).
  * Additionally, DAGs in ``critical_dags`` **or** that transitively block one
    (via ``dependencies.yaml``) also open a JiraOps on-caller alert once.

Elapsed time and historical baselines are anchored on the earliest
``execute-job-cluster*`` task start when that task exists for the run (so sensor /
pre-cluster wait is excluded). DAGs without that task keep full ``dag_run`` wall time.

Both alert paths include the transitive list of downstream ``bietlejuice.dw_*`` DAGs
impacted by the slow run, computed each cycle from the deployed ``dependencies.yaml``.

Real alerts are only sent when ``environment == prod`` (or a force_send test); otherwise
the DAG logs what it *would* send (so Forno/local runs still exercise the queries).
"""

from __future__ import annotations

import json
import math
import os
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pendulum
import requests
from airflow import DAG
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

# Airflow Variables.
JIRA_OPS_VARIABLE = "JIRA_OPS_ONCALL_APIKEY"
DEDUP_VARIABLE_KEY = "DAG_RUNTIME_MONITORING_ALERTED_RUNS"

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
        COUNT(ti.task_id) > 0 AS has_execute_job_cluster
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
                dr.end_date - COALESCE(MIN(ti.start_date), dr.start_date)
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


def _build_alert_text(finding: dict) -> str:
    """JiraOps description — same multiline layout as the Chat initial alert."""
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
    return {
        "dag_id": finding["dag_id"],
        "run_id": finding["run_id"],
        "tier": finding["tier"],
        "first_alert_ts": first_alert_ts,
        "baseline_s": finding["baseline_s"],
        "threshold_s": finding["threshold_s"],
        "percentile": finding["percentile"],
        "history_count": finding["history_count"],
        "impacted_dw_dags": impacted,
        "impacted_dw_count": finding.get("impacted_dw_count", len(impacted)),
        # ISO start used for elapsed (execute-job-cluster or dag_run); follow-ups reuse it.
        "work_start_date": finding.get("work_start_date"),
        "owner": finding.get("owner") or _UNKNOWN_OWNER,
    }


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


def _initial_text(entry: dict, elapsed_s: float) -> str:
    return _slowness_body(
        entry,
        elapsed_s,
        headline=f"🐌 *{entry['dag_id']}* running slower than usual",
        include_run=True,
        include_impact=True,
        footer="Tracking until it finishes.",
    )


def _update_text(
    entry: dict, elapsed_s: float, *, impacted_dw_count: int | None = None
) -> str:
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
    """
    critical = set(critical_dags or ())
    ledger = {}
    for run_key, value in raw.items():
        dag_id, _, run_id = run_key.partition("|")
        default_tier = "critical" if dag_id in critical else "standard"
        if isinstance(value, dict):
            entry = dict(value)
            entry.setdefault("dag_id", dag_id)
            entry.setdefault("run_id", run_id)
            entry.setdefault("tier", default_tier)
            ledger[run_key] = entry
        else:
            ledger[run_key] = {
                "dag_id": dag_id,
                "run_id": run_id,
                "tier": default_tier,
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
        f"webhook_configured={'yes' if webhook_url else 'no'}, "
        # test_webhook value redacted so a throwaway URL never lands in logs
        f"test={{simulate:{opts['simulate']}, dry_run:{opts['dry_run']}, "
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
    if opts["simulate"]:
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
    _enrich_findings_with_dw_impact(findings, downstream_index)
    _assign_alert_tiers(findings, config["critical_dags"], downstream_index)

    ledger = _normalize_ledger(
        _load_dedup_state(), critical_dags=config["critical_dags"]
    )
    owners_by_dag = _fetch_dag_owners(
        session,
        {f["dag_id"] for f in findings} | {e["dag_id"] for e in ledger.values()},
    )
    _attach_owners(findings, owners_by_dag)
    _backfill_ledger_owners(ledger, owners_by_dag)
    for f in findings:
        print(f"   • [{f['tier']}] {_build_alert_text(f)}")
    print(
        f"⏱️ {len(findings)} anomalous run(s); tracking {len(ledger)} run(s) for follow-up."
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
    _follow_up_tracked_runs(session, ledger, gchat_dest, now, downstream_index)

    # 2) Open new incidents for anomalies not yet tracked (and not just closed above).
    for finding in findings:
        key = _run_key(finding["dag_id"], finding["run_id"])
        if key in ledger or key in already_tracked:
            continue
        entry = _entry_from_finding(finding, first_alert_ts=now.isoformat())
        # Every anomaly goes to Chat (lifecycle). Critical tier also pages JiraOps.
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
            _initial_text(entry, finding["elapsed_s"]),
            _thread_key(finding["dag_id"], finding["run_id"]),
        )
        if jira_ok and chat_ok:
            ledger[key] = entry

    _save_ledger(ledger)


def _deliver_initial(finding, gchat_dest, jira_team, is_test) -> None:
    """Send the initial alert for one finding (used by simulate mode).

    Chat always; JiraOps additionally for critical tier (when test team is set).
    """
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
        _initial_text(entry, finding["elapsed_s"]),
        _thread_key(finding["dag_id"], finding["run_id"]),
    )


def _follow_up_tracked_runs(
    session, ledger: dict, gchat_dest, now: datetime, downstream_index: dict | None
) -> None:
    """Fetch the current state of tracked runs and apply follow-up messaging."""
    if not ledger:
        return
    states = _fetch_run_states(session, list(ledger.values()))
    _apply_follow_up(ledger, states, gchat_dest, now, downstream_index)


def _apply_follow_up(
    ledger: dict,
    states: dict,
    gchat_dest,
    now: datetime,
    downstream_index: dict | None = None,
) -> None:
    """For each tracked run, post an update (still running) or a closing message
    (terminal), and drop terminal/vanished runs from the ledger. Mutates ledger in place.

    Every tracked run gets Chat follow-ups (critical tier also had an initial JiraOps
    page; the Chat thread is still tracked to closure).

    Closing posts must succeed before the run is dropped — same delivery gate as the
    initial alert — so a failed ✅/❌ webhook is retried next cycle.

    Elapsed / terminal duration prefer ledger ``work_start_date`` (or joined
    ``work_start``) so Chat follow-ups stay aligned with the job-cluster clock.
    """
    for key, entry in list(ledger.items()):
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


with DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_PLATFORM,
        "start_date": datetime(2026, 7, 16, 0, 0, 0, tzinfo=LOCAL_TZ),
    },
    description=(
        "Every 30 min, flags running DAGs whose elapsed time is anomalous vs their own "
        "recent successful runs (relative P-percentile baseline, no hardcoded thresholds). "
        "Every anomaly goes to Google Chat (tracked to closure); DAGs in critical_dags "
        "or that block them also page JiraOps on-caller."
    ),
    schedule="*/30 * * * *",
    catchup=False,
    tags=["monitoring", "platform", "runtime-anomaly"],
) as dag:
    PythonOperator(
        task_id="monitor_dag_runtimes",
        python_callable=monitor_dag_runtimes,
    )
