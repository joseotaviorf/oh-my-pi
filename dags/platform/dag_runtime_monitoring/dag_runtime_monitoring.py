"""
airflow parsing enforcement

Note: this line above forces Airflow to parse this file for implemented DAGs.

Runtime-anomaly monitor. Every 30 minutes it inspects every currently-running DAG
run and flags any whose elapsed time is anomalous *relative to that same DAG's own
recent successful runs* (P<percentile> of the last <lookback_runs> durations times a
small factor) — there are no hardcoded per-DAG time thresholds.

Alerting is tiered:
  * DAGs in the configured ``critical_dags`` list (highest downstream dw_* impact)
    open a JiraOps on-caller alert (one per DAG).
  * Every other over-baseline DAG is reported in a single Google Chat webhook
    message (non-paging, informational).

A dedup state (Airflow Variable) prevents the same slow run from re-alerting every
cycle. Real alerts are only sent when ``environment == prod``; otherwise the DAG logs
what it *would* send (so Forno/local runs still exercise the queries and logic).
"""

from __future__ import annotations

import json
import math
import os
from datetime import datetime, timedelta, timezone

import pendulum
from airflow import DAG
from airflow.models import Variable
from airflow.operators.python import PythonOperator
from airflow.utils.db import provide_session
from sqlalchemy import bindparam, text

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.jiraops.jiraops_client import JiraOpsClient
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message

DAG_NAME = "dag_runtime_monitoring"
DAG_ID = f"bietlejuice.{DAG_NAME}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")

# Airflow Variables.
JIRA_OPS_VARIABLE = "JIRA_OPS_ONCALL_APIKEY"
DEDUP_VARIABLE_KEY = "DAG_RUNTIME_MONITORING_ALERTED_RUNS"

# Config fallbacks used when a key is missing from prod_conf.yml / forno_conf.yml.
_DEFAULT_CONFIG = {
    "critical_dags": [],
    "lookback_days": 7,
    "min_history_runs": 3,
    "percentile": 90,
    "factor": 1.1,
}

# Only "real" automatic runs count — scheduled, dataset-triggered, or mediator-triggered.
# Manual/backfill runs resolve to TEST_RUN in DatasetService._get_run_type (prod callbacks
# skip them), so we exclude them from both alerting and the baseline. dag_run.conf is a
# pickled column (not JSON-queryable), so we rely on the native run_type / run_id signals.
_REAL_RUN_FILTER = (
    "(run_type IN ('scheduled', 'dataset_triggered') "
    "OR run_id LIKE 'mediator_trig\\_\\_%' ESCAPE '\\')"
)

_RUNNING_QUERY = text(
    f"""
    SELECT dag_id, run_id, start_date
    FROM dag_run
    WHERE state = 'running'
      AND start_date IS NOT NULL
      AND dag_id != :self_dag_id
      AND {_REAL_RUN_FILTER}
    """
)

# Baseline is built from successful runs that finished within the lookback window
# (end_date >= :since), rather than a fixed count of recent runs.
_HISTORY_QUERY = text(
    f"""
    SELECT dag_id, EXTRACT(EPOCH FROM (end_date - start_date)) AS duration_s
    FROM dag_run
    WHERE state = 'success'
      AND start_date IS NOT NULL
      AND end_date IS NOT NULL
      AND {_REAL_RUN_FILTER}
      AND dag_id IN :dag_ids
      AND end_date >= :since
    """
).bindparams(bindparam("dag_ids", expanding=True))


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


def _evaluate_runtime(
    elapsed_s: float,
    history_durations_s: list,
    *,
    percentile: float,
    factor: float,
    min_history: int,
) -> dict | None:
    """
    Decide whether a running DAG is anomalously slow vs its own recent history.

    Returns a finding dict when ``elapsed_s`` exceeds ``P<percentile> * factor`` of the
    historical durations, else ``None``. Returns ``None`` when there is not enough
    history to form a reliable baseline (avoids false alarms on new/sparse DAGs).
    """
    if len(history_durations_s) < min_history:
        return None
    baseline = _percentile(history_durations_s, percentile)
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


def _evaluate_all(
    running_rows, durations_by_dag: dict, now: datetime, config: dict
) -> list:
    """Build findings for every running run that is over its relative baseline."""
    critical = set(config["critical_dags"])
    findings = []
    for row in running_rows:
        history = durations_by_dag.get(row.dag_id, [])
        elapsed_s = (now - row.start_date).total_seconds()
        result = _evaluate_runtime(
            elapsed_s,
            history,
            percentile=config["percentile"],
            factor=config["factor"],
            min_history=config["min_history_runs"],
        )
        if result is None:
            continue
        result.update(
            dag_id=row.dag_id,
            run_id=row.run_id,
            history_count=len(history),
            percentile=config["percentile"],
            tier="critical" if row.dag_id in critical else "standard",
        )
        findings.append(result)
    return findings


def _build_alert_text(finding: dict) -> str:
    return (
        f"*{finding['dag_id']}* runtime anomaly — running for "
        f"{_format_duration(finding['elapsed_s'])}; "
        f"P{finding['percentile']} of the last {finding['history_count']} successful runs is "
        f"{_format_duration(finding['baseline_s'])} "
        f"({finding['pct_over']}% over baseline). run_id={finding['run_id']}"
    )


def _build_gchat_text(findings: list) -> str:
    header = (
        f"⏱️ *DAG runtime anomalies* — {len(findings)} DAG(s) running longer than usual "
        f"({datetime.now().strftime('%Y-%m-%d %H:%M')})"
    )
    lines = [f"• {_build_alert_text(f)}" for f in findings]
    return "\n".join([header, *lines])


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
    dag_id = finding["dag_id"]
    run_id = finding["run_id"]
    tags = [dag_id, "runtime anomaly", "critical"]
    if test:
        tags.append("test")
    try:
        creds = json.loads(Variable.get(JIRA_OPS_VARIABLE))
        client = JiraOpsClient(creds)
        response = client.create_alert(
            message=f"{'[TEST] ' if test else ''}DAG runtime anomaly: {dag_id}",
            description=_build_alert_text(finding),
            tags=tags,
            extra_properties={
                "DAG": dag_id,
                "RunId": run_id,
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


def _send_gchat_alerts(findings: list, webhook_url: str | None) -> bool:
    """Post one batched gchat message for the standard tier. Returns True on success.

    The message is all-or-nothing (a single batched post), so the return value applies
    to every finding passed in.
    """
    if not webhook_url:
        print(
            "⚠️  gchat webhook not configured "
            f"(Variable behind notification_webhooks_keys.{DAG_NAME}). "
            "Skipping standard-tier notification; runs will be retried next cycle."
        )
        return False
    try:
        message = Message(content=_build_gchat_text(findings), destination=webhook_url)
        sent = GChatService.send_message(message)
    except Exception as error:  # noqa: BLE001 - best-effort alerting, keep going
        print(f"❌ Failed to send gchat notification: {error}. Will retry next cycle.")
        return False
    if sent:
        print(f"✅ gchat notification sent for {len(findings)} standard-tier DAG(s).")
    else:
        print(
            "❌ gchat notification not sent; standard-tier runs will be retried next cycle."
        )
    return bool(sent)


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
        "dry_run": bool(conf.get("dry_run", simulate and not force_send)),
        "force_send": force_send,
        "test_webhook": conf.get("test_webhook"),
        "test_responder_team_id": conf.get("test_responder_team_id"),
        "only_dags": _as_str_list(conf.get("only_dags")),
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
        f"webhook_configured={'yes' if webhook_url else 'no'}, "
        # test_webhook value redacted so a throwaway URL never lands in logs
        f"test={{simulate:{opts['simulate']}, dry_run:{opts['dry_run']}, "
        f"force_send:{opts['force_send']}, test_webhook:{'yes' if opts['test_webhook'] else 'no'}, "
        f"test_team:{'yes' if opts['test_responder_team_id'] else 'no'}, "
        f"only_dags:{len(opts['only_dags']) if opts['only_dags'] else 0}}}"
    )

    # Build findings: fabricated (simulate) or evaluated from the metadata DB.
    # all_running_rows is the full active set (used for dedup pruning); running_rows is the
    # possibly-narrowed set we actually evaluate.
    if opts["simulate"]:
        findings = _synthetic_findings(config, opts["simulate_dags"])
        all_running_rows = None
        print(f"🧪 simulate mode: fabricated {len(findings)} synthetic finding(s).")
    else:
        all_running_rows = _fetch_running_runs(session)
        running_rows = all_running_rows
        if opts["only_dags"]:
            wanted = set(opts["only_dags"])
            running_rows = [row for row in all_running_rows if row.dag_id in wanted]
        if not running_rows:
            print("✅ No running DAG runs to evaluate.")
            return
        now = datetime.now(timezone.utc)
        since = now - timedelta(days=config["lookback_days"])
        durations_by_dag = _fetch_recent_durations(
            session, {row.dag_id for row in running_rows}, since
        )
        findings = _evaluate_all(running_rows, durations_by_dag, now, config)

    if not findings:
        print("✅ No runtime anomalies detected.")
        return

    # Dedup for real runs only; simulated runs are always treated as fresh.
    if opts["simulate"]:
        fresh = findings
        alerted_state = None
    else:
        alerted_state = _load_dedup_state()
        fresh = [
            f
            for f in findings
            if _run_key(f["dag_id"], f["run_id"]) not in alerted_state
        ]
        print(
            f"⏱️ {len(findings)} anomalous run(s); {len(fresh)} new after dedup "
            f"({len(findings) - len(fresh)} already alerted)."
        )

    for f in findings:
        print(f"   • [{f['tier']}] {_build_alert_text(f)}")

    if not fresh:
        if alerted_state is not None:
            _prune_and_save_state(alerted_state, all_running_rows)
        return

    critical = [f for f in fresh if f["tier"] == "critical"]
    standard = [f for f in fresh if f["tier"] == "standard"]

    # Deliver in prod, or when force_send explicitly overrides the gate for a test.
    deliver = (environment == "prod") or opts["force_send"]
    if opts["dry_run"] or not deliver:
        reason = (
            "dry_run"
            if opts["dry_run"]
            else f"environment={environment} and force_send=false"
        )
        print(
            f"ℹ️  Not delivering ({reason}). Would page JiraOps for {len(critical)} "
            f"critical DAG(s) and post gchat for {len(standard)} standard DAG(s)."
        )
        return

    # Test-destination overrides (test_webhook / test_responder_team_id) only apply to a
    # force_send test delivery — never to a real prod run, which must use the configured
    # webhook and the default on-call team.
    is_test = opts["force_send"]
    gchat_dest = (opts["test_webhook"] if is_test else None) or webhook_url
    jira_team = opts["test_responder_team_id"] if is_test else None

    # Only successfully-delivered runs are recorded; failed/skipped ones retry next cycle.
    delivered_keys: set = set()
    for finding in critical:
        if is_test and not jira_team:
            print(
                f"⚠️  Refusing to page real on-call from a test trigger for "
                f"{finding['dag_id']} — pass test_responder_team_id to route a critical "
                "test alert. Logging only."
            )
            continue
        if _send_jira_alert(finding, responder_team_id=jira_team, test=is_test):
            delivered_keys.add(_run_key(finding["dag_id"], finding["run_id"]))
    if standard and _send_gchat_alerts(standard, gchat_dest):
        delivered_keys.update(_run_key(f["dag_id"], f["run_id"]) for f in standard)

    # Record delivered runs (real runs only) and forget runs no longer active. Prune uses
    # the FULL active set (all_running_rows), so an only_dags-scoped run never drops other
    # still-running DAGs' dedup entries.
    if alerted_state is not None:
        now_iso = datetime.now(timezone.utc).isoformat()
        for key in delivered_keys:
            alerted_state[key] = now_iso
        _prune_and_save_state(alerted_state, all_running_rows)


def _prune_and_save_state(alerted_state: dict, running_rows) -> None:
    """Drop dedup keys whose run is no longer running, then persist the state."""
    active_keys = {_run_key(row.dag_id, row.run_id) for row in running_rows}
    pruned = {k: v for k, v in alerted_state.items() if k in active_keys}
    Variable.set(DEDUP_VARIABLE_KEY, json.dumps(pruned))


with DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_PLATFORM,
        "start_date": datetime(2026, 7, 16, 0, 0, 0, tzinfo=LOCAL_TZ),
    },
    description=(
        "Every 30 min, flags running DAGs whose elapsed time is anomalous vs their own "
        "recent successful runs (relative P-percentile baseline, no hardcoded thresholds). "
        "Critical DAGs page JiraOps on-caller; the rest are reported to a Google Chat webhook."
    ),
    schedule="*/30 * * * *",
    catchup=False,
    tags=["monitoring", "platform", "runtime-anomaly"],
) as dag:
    PythonOperator(
        task_id="monitor_dag_runtimes",
        python_callable=monitor_dag_runtimes,
    )
