"""Shared reference-prod selection for cluster validation trigger and outcomes SQL.

Mirrors ``trigger_cluster_validation_dags.py`` ``--from-prod-run`` logic so
validation runs pair with the same prod baseline the batch trigger used.
"""

from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone
from typing import Any, Literal

DATE_PARAM_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")

# Airflow dag_run wall time — matches trigger_cluster_validation_dags.py.
MIN_PROD_RUN_DURATION_SECONDS = 8 * 60
# Hard floor; never relax below this in SQL or Python selection.
MIN_PROD_RUN_DURATION_FLOOR_SECONDS = 5 * 60
# Databricks fact_databricks_dag_run baseline guard (belt-and-suspenders).
MIN_PROD_DATABRICKS_WALL_SECONDS = 5 * 60

DEFAULT_PROD_RUN_LOOKBACK_DAYS = 14

LoadWindowSource = Literal[
    "conf",
    "data_interval",
    "exception:text2filter_single_day",
    "exception:cyber_legal_3day_window",
    "exception:greenhouse_v3_single_day",
    "exception:maestro_next_day_ingest",
    "exception:conversation_explorer_pinned_day",
]


def is_valid_date_param(value: Any) -> bool:
    return isinstance(value, str) and bool(DATE_PARAM_PATTERN.match(value))


def parse_airflow_timestamp(value: Any) -> datetime | None:
    if not value or not isinstance(value, str):
        return None
    normalized = value.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def to_utc_date_str(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y-%m-%d")


def dag_run_id_from_payload(run: dict[str, Any]) -> str | None:
    run_id = run.get("dag_run_id") or run.get("run_id") or run.get("id_run")
    return str(run_id) if run_id else None


def dag_run_duration_seconds(run: dict[str, Any]) -> float | None:
    start = parse_airflow_timestamp(run.get("start_date") or run.get("ts_started"))
    end = parse_airflow_timestamp(run.get("end_date") or run.get("ts_ended"))
    if start is None or end is None:
        return None
    return max(0.0, (end - start).total_seconds())


def ensure_exclusive_load_end(conf: dict[str, str]) -> dict[str, str]:
    start = conf.get("load_start_date")
    end = conf.get("load_end_date")
    if not (is_valid_date_param(start) and is_valid_date_param(end)):
        return conf
    if start >= end:
        bumped_end = (datetime.strptime(end, "%Y-%m-%d") + timedelta(days=1)).strftime(
            "%Y-%m-%d"
        )
        return {**conf, "load_end_date": bumped_end}
    return conf


def load_window_from_prod_dag_run(
    run: dict[str, Any],
) -> tuple[dict[str, str], LoadWindowSource] | None:
    run_conf = run.get("conf") or run.get("configuration")
    if isinstance(run_conf, dict):
        start = run_conf.get("load_start_date")
        end = run_conf.get("load_end_date")
        if is_valid_date_param(start) and is_valid_date_param(end):
            return (
                ensure_exclusive_load_end(
                    {
                        "run_type": "test_run",
                        "load_start_date": str(start),
                        "load_end_date": str(end),
                    }
                ),
                "conf",
            )

    interval_start = parse_airflow_timestamp(
        run.get("data_interval_start") or run.get("ts_data_interval_started")
    )
    interval_end = parse_airflow_timestamp(
        run.get("data_interval_end") or run.get("ts_data_interval_ended")
    )
    if interval_start is None or interval_end is None:
        return None

    load_end_dt = interval_end - timedelta(days=1)
    return (
        ensure_exclusive_load_end(
            {
                "run_type": "test_run",
                "load_start_date": to_utc_date_str(interval_start),
                "load_end_date": to_utc_date_str(load_end_dt),
            }
        ),
        "data_interval",
    )


def has_prod_success_within_days(
    runs: list[dict[str, Any]],
    *,
    recency_days: int,
    now: datetime,
    min_duration_seconds: float = MIN_PROD_RUN_DURATION_SECONDS,
) -> bool:
    cutoff = now - timedelta(days=recency_days)
    for run in runs:
        end = parse_airflow_timestamp(run.get("end_date") or run.get("ts_ended"))
        if end is None or end < cutoff:
            continue
        duration = dag_run_duration_seconds(run)
        if duration is None or duration < min_duration_seconds:
            continue
        return True
    return False


def select_reference_prod_run(
    runs: list[dict[str, Any]],
    *,
    lookback_days: int,
    now: datetime,
    min_duration_seconds: float = MIN_PROD_RUN_DURATION_SECONDS,
) -> dict[str, Any] | None:
    effective_min = max(min_duration_seconds, MIN_PROD_RUN_DURATION_FLOOR_SECONDS)
    cutoff = now - timedelta(days=lookback_days)
    candidates: list[tuple[float, datetime, dict[str, Any]]] = []

    for run in runs:
        end = parse_airflow_timestamp(run.get("end_date") or run.get("ts_ended"))
        start = parse_airflow_timestamp(run.get("start_date") or run.get("ts_started"))
        reference = end or start
        if reference is None or reference < cutoff:
            continue
        duration = dag_run_duration_seconds(run)
        if duration is None or duration < effective_min:
            continue
        tie_break = start or end or reference
        candidates.append((duration, tie_break, run))

    if not candidates:
        return None

    _duration, _tie_break, selected = min(
        candidates,
        key=lambda item: (item[0], -item[1].timestamp()),
    )
    return selected


def validation_conf_with_reference(
    conf: dict[str, str],
    *,
    reference_prod_dag_run_id: str | None,
    reference_prod_duration_seconds: float | None = None,
    window_source: LoadWindowSource | None = None,
) -> dict[str, str]:
    """Augment validation trigger conf with durable reference-prod linkage."""
    enriched = dict(conf)
    if reference_prod_dag_run_id:
        enriched["reference_prod_dag_run_id"] = reference_prod_dag_run_id
    if reference_prod_duration_seconds is not None:
        enriched["reference_prod_duration_seconds"] = str(
            round(reference_prod_duration_seconds, 1)
        )
    if window_source is not None:
        enriched["window_source"] = window_source
    return enriched
