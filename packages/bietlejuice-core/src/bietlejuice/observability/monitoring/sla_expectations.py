"""Load domain-owned SLA expectation files from the dags/ tree."""

from __future__ import annotations

import glob
import json
import logging
import os
from dataclasses import dataclass
from typing import Any

import yaml

from bietlejuice.observability.monitoring.constants import (
    DEFAULT_SLA_TIMEZONE,
    SLA_GLOB,
    WEEKDAY_INDEX,
    WEEKDAY_SUGAR,
)

logger = logging.getLogger(__name__)

_WEEKDAY_NAMES = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")
_TZ_SHORT = {"America/Sao_Paulo": "BRT", "UTC": "UTC"}


@dataclass(frozen=True)
class ArrivalExpectation:
    days_of_week: set[int] | None = None
    earliest_hour: int | None = None
    mute: bool = False
    timezone: str = DEFAULT_SLA_TIMEZONE
    reason: str | None = None


def format_arrival_expectation_brief(
    expectation: ArrivalExpectation | None,
) -> str:
    """Compact SLA line for GChat alerts."""
    if expectation is None:
        return "no SLA (any empty partition alerts)"

    if expectation.days_of_week is None:
        cadence = "daily"
    elif expectation.days_of_week == WEEKDAY_SUGAR["weekdays"]:
        cadence = "weekdays"
    else:
        cadence = "custom days"

    if expectation.earliest_hour is not None:
        tz_label = _TZ_SHORT.get(expectation.timezone, expectation.timezone)
        return f"{cadence} from {expectation.earliest_hour:02d}h {tz_label}"
    return cadence


def format_arrival_expectation_summary(
    expectation: ArrivalExpectation | None,
) -> str:
    """Human-readable arrival SLA for alert messages."""
    if expectation is None:
        return "none configured (alert on any empty run partition)"

    parts: list[str] = []
    if expectation.days_of_week is None:
        parts.append("every day")
    elif expectation.days_of_week == WEEKDAY_SUGAR["weekdays"]:
        parts.append("weekdays (Mon–Fri)")
    else:
        day_labels = [
            _WEEKDAY_NAMES[index]
            for index in sorted(expectation.days_of_week)
            if 0 <= index < len(_WEEKDAY_NAMES)
        ]
        parts.append(", ".join(day_labels) if day_labels else "custom days")

    if expectation.earliest_hour is not None:
        parts.append(
            f"data expected from {expectation.earliest_hour:02d}:00 "
            f"({expectation.timezone}) on run day"
        )
    else:
        parts.append("no earliest-hour gate")

    summary = "; ".join(parts)
    if expectation.reason:
        return f"{summary} — {expectation.reason}"
    return summary


def _parse_days_of_week(value: object) -> set[int] | None:
    if value is None:
        return None
    if isinstance(value, str):
        sugar = WEEKDAY_SUGAR.get(value.lower())
        if sugar is not None or value.lower() == "all":
            return sugar
        day_index = WEEKDAY_INDEX.get(value.lower())
        if day_index is not None:
            return {day_index}
        return None
    if isinstance(value, list):
        days: set[int] = set()
        for entry in value:
            if not isinstance(entry, str):
                continue
            day_index = WEEKDAY_INDEX.get(entry.lower())
            if day_index is not None:
                days.add(day_index)
        return days or None
    return None


def _parse_arrival_expectation(arrival: dict) -> ArrivalExpectation:
    earliest_hour = arrival.get("earliest_hour")
    if earliest_hour is not None:
        earliest_hour = int(earliest_hour)
    timezone = arrival.get("timezone") or DEFAULT_SLA_TIMEZONE
    return ArrivalExpectation(
        days_of_week=_parse_days_of_week(arrival.get("days_of_week")),
        earliest_hour=earliest_hour,
        mute=bool(arrival.get("mute", False)),
        timezone=str(timezone),
        reason=_optional_str(arrival.get("reason")),
    )


def _optional_str(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _expectation_to_dict(expectation: ArrivalExpectation) -> dict[str, Any]:
    days = expectation.days_of_week
    if days is None:
        days_payload: Any = None
    else:
        days_payload = sorted(days)
    return {
        "days_of_week": days_payload,
        "earliest_hour": expectation.earliest_hour,
        "mute": expectation.mute,
        "timezone": expectation.timezone,
        "reason": expectation.reason,
    }


def _expectation_from_dict(payload: dict[str, Any]) -> ArrivalExpectation:
    days_raw = payload.get("days_of_week")
    days_of_week: set[int] | None
    if days_raw is None:
        days_of_week = None
    else:
        days_of_week = {int(day) for day in days_raw}
    earliest_hour = payload.get("earliest_hour")
    if earliest_hour is not None:
        earliest_hour = int(earliest_hour)
    return ArrivalExpectation(
        days_of_week=days_of_week,
        earliest_hour=earliest_hour,
        mute=bool(payload.get("mute", False)),
        timezone=str(payload.get("timezone") or DEFAULT_SLA_TIMEZONE),
        reason=_optional_str(payload.get("reason")),
    )


def dump_expectations_json(
    expectations: dict[tuple[str, str], ArrivalExpectation],
) -> str:
    """Serialize expectations for staging on S3 (EMR spark job input)."""
    payload = {
        f"{database}|{table}": _expectation_to_dict(expectation)
        for (database, table), expectation in expectations.items()
    }
    return json.dumps(payload, sort_keys=True)


def load_expectations_from_json(text: str) -> dict[tuple[str, str], ArrivalExpectation]:
    """Deserialize expectations staged for the EMR spark job."""
    raw = json.loads(text or "{}")
    if not isinstance(raw, dict):
        return {}
    expectations: dict[tuple[str, str], ArrivalExpectation] = {}
    for key, value in raw.items():
        if not isinstance(key, str) or "|" not in key or not isinstance(value, dict):
            continue
        database, table = key.split("|", 1)
        expectations[(database, table)] = _expectation_from_dict(value)
    return expectations


def load_sla_expectations(dags_root: str) -> dict[tuple[str, str], ArrivalExpectation]:
    """Glob ``dags/**/sla/**/*.yml`` and index by ``(database_name, table_name)``."""
    pattern = os.path.join(dags_root, SLA_GLOB)
    expectations: dict[tuple[str, str], ArrivalExpectation] = {}
    for path in sorted(glob.glob(pattern, recursive=True)):
        try:
            with open(path, encoding="utf-8") as handle:
                content = yaml.safe_load(handle) or {}
            if not isinstance(content, dict):
                logger.warning("SLA file is not a mapping: %s", path)
                continue
            database_name = content.get("database_name")
            table_name = content.get("table_name")
            if not database_name or not table_name:
                logger.warning("SLA file missing database_name/table_name: %s", path)
                continue
            arrival = content.get("arrival")
            if arrival is None:
                continue
            if not isinstance(arrival, dict):
                logger.warning("SLA arrival facet is not a mapping: %s", path)
                continue
            key = (str(database_name).strip(), str(table_name).strip())
            expectations[key] = _parse_arrival_expectation(arrival)
        except Exception:
            logger.warning("Failed to parse SLA file: %s", path, exc_info=True)
    return expectations
