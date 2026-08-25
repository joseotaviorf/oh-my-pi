"""Judgment logic for stale-data signals (MAX(column) older than SLA threshold)."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from bietlejuice.observability.monitoring.constants import (
    GCHAT_TEXT_MAX,
    SIGNAL_STALE_DATA,
    UNKNOWN_OWNER,
    UNKNOWN_TEAM,
)
from bietlejuice.observability.monitoring.sla_expectations import (
    StaleDataCheck,
    format_stale_data_sla_brief,
)

ALERT_HEADER = "⚠️ Stale Data Detected"
Finding = dict[str, Any]


def _display_owner(value: str | None, unknown_label: str) -> str:
    if not value or value == unknown_label:
        return unknown_label
    return value


def format_environment_tag(environment: str | None) -> str:
    normalized = (environment or "").strip().lower()
    if normalized == "prod":
        return "[PROD]"
    if normalized == "forno":
        return "[FORNO]"
    if normalized:
        return f"[{normalized.upper()}]"
    return "[UNKNOWN]"


def _ensure_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def judge_stale_data(
    *,
    database: str,
    table: str,
    check: StaleDataCheck,
    latest_data_at: datetime | None,
    collection_method: str,
    layer: str | None = None,
    now: datetime | None = None,
) -> Finding | None:
    """Return a finding when ``latest_data_at`` is missing or older than the SLA."""
    now_dt = _ensure_utc(now or datetime.now(timezone.utc))
    if latest_data_at is None:
        age_hours = None
        is_stale = True
    else:
        latest_utc = _ensure_utc(latest_data_at)
        age_hours = (now_dt - latest_utc).total_seconds() / 3600.0
        is_stale = age_hours > check.max_age_hours
    if not is_stale:
        return None
    return {
        "signal_type": SIGNAL_STALE_DATA,
        "database": database,
        "table": table,
        "layer": layer,
        "column": check.column,
        "max_age_hours": check.max_age_hours,
        "latest_data_at": latest_data_at,
        "age_hours": age_hours,
        "collection_method": collection_method,
        "sla_summary": format_stale_data_sla_brief(check),
    }


def finding_thread_key(finding: Finding) -> str:
    return (
        f"{finding['signal_type']}:{finding['database']}.{finding['table']}:"
        f"{finding['column']}"
    )


def format_finding_message(finding: Finding) -> str:
    table_fqn = f"{finding['database']}.{finding['table']}"
    column = finding.get("column") or "unknown"
    max_age_hours = finding.get("max_age_hours")
    latest_data_at = finding.get("latest_data_at")
    age_hours = finding.get("age_hours")
    table_owner = _display_owner(finding.get("table_owner"), UNKNOWN_OWNER)
    team_owner = _display_owner(finding.get("team_owner"), UNKNOWN_TEAM)
    env_tag = format_environment_tag(finding.get("environment"))
    contact = (
        f"{table_owner} · {team_owner}"
        if table_owner != UNKNOWN_OWNER and team_owner != UNKNOWN_TEAM
        else table_owner
        if table_owner != UNKNOWN_OWNER
        else team_owner
    )
    if latest_data_at is None:
        latest_label = "none"
        age_label = "unknown"
    else:
        latest_label = _ensure_utc(latest_data_at).strftime("%Y-%m-%d %H:%M UTC")
        age_label = f"{age_hours:.1f}h" if age_hours is not None else "unknown"
    lines = [
        f"{env_tag} {ALERT_HEADER}",
        f"Table: `{table_fqn}`",
        f"Column `{column}` latest value: {latest_label} (age {age_label}).",
        f"SLA: max age {max_age_hours}h.",
        "Action: verify upstream ingestion and the load pipeline.",
        f"Contact: {contact}",
    ]
    text = "\n".join(lines)
    if len(text) > GCHAT_TEXT_MAX:
        return text[: GCHAT_TEXT_MAX - 3] + "..."
    return text
