"""DAG-specific validation conf resolvers when generic load-window logic does not apply.

Register prod DAG ids in ``VALIDATION_CONF_EXCEPTIONS`` when ``load_window_from_prod_dag_run``
derives the wrong ``load_start_date`` / ``load_end_date`` for validation triggers.
"""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime, timedelta
from typing import Any

from scripts.cluster_validation_reference import (
    LoadWindowSource,
    ensure_exclusive_load_end,
    is_valid_date_param,
    load_window_from_prod_dag_run,
    parse_airflow_timestamp,
    to_utc_date_str,
)

ValidationConfResolver = Callable[
    [dict[str, Any]], tuple[dict[str, str], LoadWindowSource] | None
]

TEXT2FILTER_SINGLE_DAY: LoadWindowSource = "exception:text2filter_single_day"
CYBER_LEGAL_3DAY_WINDOW: LoadWindowSource = "exception:cyber_legal_3day_window"
GREENHOUSE_V3_SINGLE_DAY: LoadWindowSource = "exception:greenhouse_v3_single_day"
MAESTRO_NEXT_DAY_INGEST: LoadWindowSource = "exception:maestro_next_day_ingest"

DAG_TEXT2FILTER_EVALS = "bietlejuice.text2filter_evals"
DAG_CYBER_LEGAL = "bietlejuice.cyber_legal"
DAG_GREENHOUSE_V3 = "bietlejuice.greenhouse_v3"
DAG_DEMAND_BALANCER_SERVICE = "bietlejuice.demand_balancer_service"
DAG_SEARCH_METRICS_SERVICE = "bietlejuice.search_metrics_service"


def _conf_load_start_from_run(run: dict[str, Any]) -> str | None:
    run_conf = run.get("conf") or run.get("configuration")
    if not isinstance(run_conf, dict):
        return None
    start = run_conf.get("load_start_date")
    if is_valid_date_param(start):
        return str(start)
    return None


def _conf_dates_from_run(run: dict[str, Any]) -> tuple[str, str] | None:
    run_conf = run.get("conf") or run.get("configuration")
    if not isinstance(run_conf, dict):
        return None
    start = run_conf.get("load_start_date")
    end = run_conf.get("load_end_date")
    if is_valid_date_param(start) and is_valid_date_param(end):
        return str(start), str(end)
    return None


def _interval_start(run: dict[str, Any]) -> datetime | None:
    return parse_airflow_timestamp(
        run.get("data_interval_start") or run.get("ts_data_interval_started")
    )


def _test_run_conf(load_start_date: str, load_end_date: str) -> dict[str, str]:
    return ensure_exclusive_load_end(
        {
            "run_type": "test_run",
            "load_start_date": load_start_date,
            "load_end_date": load_end_date,
        }
    )


def resolve_text2filter_evals_conf(
    run: dict[str, Any],
) -> tuple[dict[str, str], LoadWindowSource] | None:
    """Single-day S3 ingest partition; not a multi-day load window."""
    ingest_day = _conf_load_start_from_run(run)
    if ingest_day is None:
        interval_start = _interval_start(run)
        if interval_start is None:
            return None
        ingest_day = to_utc_date_str(interval_start)

    exclusive_end = (
        datetime.strptime(ingest_day, "%Y-%m-%d") + timedelta(days=1)
    ).strftime("%Y-%m-%d")
    return _test_run_conf(ingest_day, exclusive_end), TEXT2FILTER_SINGLE_DAY


def resolve_cyber_legal_conf(
    run: dict[str, Any],
) -> tuple[dict[str, str], LoadWindowSource] | None:
    """Match declaration Jinja: load_end = load_start + 2 days when conf is absent."""
    conf_dates = _conf_dates_from_run(run)
    if conf_dates is not None:
        start, end = conf_dates
        return _test_run_conf(start, end), "conf"

    interval_start = _interval_start(run)
    if interval_start is None:
        return None

    start_str = to_utc_date_str(interval_start)
    end_str = to_utc_date_str(interval_start + timedelta(days=2))
    return _test_run_conf(start_str, end_str), CYBER_LEGAL_3DAY_WINDOW


def resolve_greenhouse_v3_conf(
    run: dict[str, Any],
) -> tuple[dict[str, str], LoadWindowSource] | None:
    """Single-day API ingest window for Greenhouse v3 validation runs."""
    ingest_day = _conf_load_start_from_run(run)
    if ingest_day is None:
        interval_start = _interval_start(run)
        if interval_start is None:
            return None
        ingest_day = to_utc_date_str(interval_start)

    exclusive_end = (
        datetime.strptime(ingest_day, "%Y-%m-%d") + timedelta(days=1)
    ).strftime("%Y-%m-%d")
    return _test_run_conf(ingest_day, exclusive_end), GREENHOUSE_V3_SINGLE_DAY


def resolve_maestro_next_day_ingest_conf(
    run: dict[str, Any],
) -> tuple[dict[str, str], LoadWindowSource] | None:
    """S3 partition is data_interval_start + 1 day (maestro / search_monitoring layout)."""
    ingest_day = _conf_load_start_from_run(run)
    if ingest_day is None:
        interval_start = _interval_start(run)
        if interval_start is None:
            return None
        ingest_day = to_utc_date_str(interval_start + timedelta(days=1))

    exclusive_end = (
        datetime.strptime(ingest_day, "%Y-%m-%d") + timedelta(days=1)
    ).strftime("%Y-%m-%d")
    return _test_run_conf(ingest_day, exclusive_end), MAESTRO_NEXT_DAY_INGEST


VALIDATION_CONF_EXCEPTIONS: dict[str, ValidationConfResolver] = {
    DAG_TEXT2FILTER_EVALS: resolve_text2filter_evals_conf,
    DAG_CYBER_LEGAL: resolve_cyber_legal_conf,
    DAG_GREENHOUSE_V3: resolve_greenhouse_v3_conf,
    DAG_DEMAND_BALANCER_SERVICE: resolve_maestro_next_day_ingest_conf,
    DAG_SEARCH_METRICS_SERVICE: resolve_maestro_next_day_ingest_conf,
}


def resolve_validation_conf_for_dag(
    original_dag_id: str,
    reference_run: dict[str, Any],
) -> tuple[dict[str, str], LoadWindowSource] | None:
    resolver = VALIDATION_CONF_EXCEPTIONS.get(original_dag_id)
    if resolver is not None:
        return resolver(reference_run)
    return load_window_from_prod_dag_run(reference_run)
