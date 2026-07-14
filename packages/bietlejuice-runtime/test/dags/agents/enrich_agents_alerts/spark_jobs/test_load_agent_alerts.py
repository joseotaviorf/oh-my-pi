"""Tests for ``load_agent_alerts`` (registry, cron gate, dedup notify, Notification Hub).

Run::

    uv run --directory packages/bietlejuice-runtime pytest \\
        test/dags/agents/enrich_agents_alerts/spark_jobs/test_load_agent_alerts.py -q
"""

import builtins
import importlib
import os
import sys
from argparse import Namespace
from datetime import date, datetime
from unittest.mock import MagicMock, patch

import pendulum
import pytest


def _repo_root() -> str:
    cur = os.path.abspath(os.path.dirname(__file__))
    while cur != os.path.dirname(cur):
        if os.path.exists(os.path.join(cur, ".git")):
            return cur
        cur = os.path.dirname(cur)
    raise RuntimeError("Cannot find repo root")


_SRC_SPARK_JOBS = os.path.join(
    _repo_root(), "dags", "agents", "enrich_agents_alerts", "spark_jobs"
)
if _SRC_SPARK_JOBS not in sys.path:
    sys.path.insert(0, _SRC_SPARK_JOBS)

builtins.spark = MagicMock()

_IMPORT_TIME_MOCKS = {
    "bietlejuice": MagicMock(),
    "bietlejuice.base": MagicMock(),
    "bietlejuice.base.service": MagicMock(),
    "bietlejuice.base.service.dag_packages_path_service": MagicMock(),
    "bietlejuice.loaders": MagicMock(),
    "bietlejuice.loaders.delta_loader": MagicMock(),
    "bietlejuice.services": MagicMock(),
    "bietlejuice.services.configuration_service": MagicMock(),
    "quintoandar_logger": MagicMock(),
    "requests": MagicMock(),
}

with patch.dict("sys.modules", _IMPORT_TIME_MOCKS):
    _job = importlib.import_module("load_agent_alerts")

_TS = pendulum.datetime(2026, 7, 7, 2, 0, 0)

_VALID_REGISTRY_YAML = """
alerts:
  prospect_waiting_conversion_6h:
    description: Prospects stuck in WAITING_CONVERSION for more than 6 hours.
    channel: "#agents-data-alarms"
    cron: "0 */2 * * *"
    threshold: 0
    severity: Error
    id_column: id_prospect_agent
    criteria_sql: |
      SELECT id_prospect_agent
"""


def _defn(**overrides):
    base = {
        "description": "d",
        "channel": "#agents-data-alarms",
        "cron": "0 */2 * * *",
        "threshold": 0,
        "severity": "Error",
        "id_column": "id_entity",
        "criteria_sql": "SELECT id_entity",
    }
    base.update(overrides)
    return base


def _row(**fields):
    m = MagicMock()
    m.__getitem__ = lambda self, key: fields[key]
    return m


def _violations_df_mock(
    *,
    count: int,
    sample_rows: list | None = None,
    anti_join_new_count: int | None = None,
):
    """Spark DataFrame stub; every transform returns ``df`` so ``count()`` stays an ``int``."""
    df = MagicMock(name="violations_df")
    df.count.return_value = count
    for method in (
        "select",
        "filter",
        "withColumnRenamed",
        "withColumn",
        "dropDuplicates",
    ):
        getattr(df, method).return_value = df

    if anti_join_new_count is not None:
        new_df = MagicMock(name="new_after_anti_join")
        new_df.count.return_value = anti_join_new_count
        new_df.limit.return_value.collect.return_value = sample_rows or []
        df.join.return_value = new_df
    else:
        df.join.return_value = df
        df.limit.return_value.collect.return_value = sample_rows or []
    return df


@pytest.fixture(autouse=True)
def _reset_module_mocks():
    for name in (
        "DAGPackagesPathService",
        "DeltaLoader",
        "ConfigurationService",
        "requests",
    ):
        getattr(_job, name).reset_mock(return_value=True, side_effect=True)
    yield


@pytest.fixture
def mock_spark(monkeypatch):
    m = MagicMock()
    m.catalog.tableExists.return_value = False
    m.createDataFrame.return_value = MagicMock()
    monkeypatch.setattr(_job, "spark", m, raising=False)
    return m


def _patch_args(logical_ts: str = "2026-07-07T02:00:00"):
    return patch.object(
        _job,
        "parse_arguments",
        return_value=Namespace(
            environment="forno",
            datalake_bucket="5a-datalake-forno",
            dag_name="enrich_agents_alerts",
            schema="agents_validation",
            logical_ts=logical_ts,
        ),
    )


# --- Cron gate (TDD) ---


def test_cron_gate_timestamp_floors_subminute_precision():
    ts = datetime(2026, 7, 10, 12, 30, 45, 123456)
    assert _job._cron_gate_timestamp(ts) == datetime(2026, 7, 10, 12, 30, 0, 0)


@pytest.mark.parametrize(
    "logical_ts,expected_names",
    [
        (datetime(2026, 7, 10, 12, 0), {"hourly", "every_two_hours"}),
        (datetime(2026, 7, 10, 12, 30), set()),
        (datetime(2026, 7, 10, 13, 0), {"hourly"}),
        (datetime(2026, 7, 10, 14, 0), {"hourly", "every_two_hours"}),
    ],
)
def test_due_alerts_hourly_on_thirty_minute_dag_ticks(logical_ts, expected_names):
    """DAG */30; alert ``0 * * * *`` only on :00, not :30."""
    registry = {
        "hourly": _defn(cron="0 * * * *"),
        "every_two_hours": _defn(cron="0 */2 * * *"),
    }
    due = _job._due_alerts(registry, logical_ts)
    assert set(due) == expected_names


def test_due_alerts_ignore_cron_runs_on_any_tick():
    registry = {
        "smoke": _defn(cron="0 3 * * *", ignore_cron=True),
        "night_only": _defn(cron="0 3 * * *"),
    }
    due = _job._due_alerts(registry, datetime(2026, 7, 10, 12, 30))
    assert set(due) == {"smoke"}


def test_due_alerts_weekday_cron():
    registry = {"monday_9am": _defn(cron="0 9 * * 1")}
    assert "monday_9am" in _job._due_alerts(registry, datetime(2026, 7, 6, 9, 0))
    assert "monday_9am" not in _job._due_alerts(registry, datetime(2026, 7, 7, 9, 0))


@pytest.mark.parametrize(
    "expr,dt,expected",
    [
        # step on hour field (registry's every-two-hours schedule)
        ("0 */2 * * *", datetime(2026, 7, 7, 2, 0), True),
        ("0 */2 * * *", datetime(2026, 7, 7, 1, 0), False),
        # comma list
        ("0,30 * * * *", datetime(2026, 7, 10, 12, 30), True),
        ("0,30 * * * *", datetime(2026, 7, 10, 12, 15), False),
        # range
        ("1-5 * * * *", datetime(2026, 7, 10, 12, 3), True),
        ("1-5 * * * *", datetime(2026, 7, 10, 12, 6), False),
        # range with step
        ("0-20/5 * * * *", datetime(2026, 7, 10, 12, 10), True),
        ("0-20/5 * * * *", datetime(2026, 7, 10, 12, 7), False),
        # bare */step on minute
        ("*/15 * * * *", datetime(2026, 7, 10, 12, 45), True),
        ("*/15 * * * *", datetime(2026, 7, 10, 12, 46), False),
        # day-of-week, cron Sunday = 0
        ("0 9 * * 0", datetime(2026, 7, 12, 9, 0), True),  # Sunday
        ("0 9 * * 0", datetime(2026, 7, 13, 9, 0), False),  # Monday
    ],
)
def test_is_cron_due_grammar(expr, dt, expected):
    assert _job.is_cron_due(expr, dt) is expected


def test_is_cron_due_rejects_non_five_field_expressions():
    with pytest.raises(ValueError):
        _job.is_cron_due("* * * *", datetime(2026, 7, 7, 0, 0))


# --- Registry / timestamps / notify ---


def test_load_registry_requires_complete_alert_definition():
    _job.DAGPackagesPathService.get_config_file_content_in_spark_jobs.return_value = """
alerts:
  broken:
    description: x
    channel: "#agents-data-alarms"
    cron: "0 */2 * * *"
    threshold: 0
"""
    with pytest.raises(ValueError):
        _job.load_registry("enrich_agents_alerts")


def test_load_registry_rejects_unroutable_channel():
    """A channel that resolves to no Hub space fails fast at load, not mid-run."""
    _job.DAGPackagesPathService.get_config_file_content_in_spark_jobs.return_value = """
alerts:
  no_channel:
    description: x
    channel: ""
    cron: "0 */2 * * *"
    threshold: 0
    id_column: id_x
    criteria_sql: SELECT id_x
"""
    with pytest.raises(ValueError):
        _job.load_registry("enrich_agents_alerts")


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("2026-07-07T02:00:00Z", datetime(2026, 7, 7, 2, 0)),
        ("2026-07-07T02:00:00+00:00", datetime(2026, 7, 7, 2, 0)),
        ("2026-07-07T02:00:00-03:00", datetime(2026, 7, 7, 5, 0)),  # BRT -> UTC
        ("2026-07-07T02:00:00", datetime(2026, 7, 7, 2, 0)),  # naive kept as-is
    ],
)
def test_parse_logical_ts_normalizes_to_naive_utc(raw, expected):
    result = _job._parse_logical_ts(raw)
    assert result == expected
    assert result.tzinfo is None


def test_check_timestamps_coerce_pendulum_logical_ts_to_stdlib():
    dt_check, ts_check = _job._check_timestamps(_TS)
    assert type(dt_check) is date
    assert type(ts_check) is datetime


def test_notify_on_breach_posts_inmetro_payload_with_hub_space_from_channel():
    hub_base = (
        "https://notification-hub-internal-api.quintoandar.com.br/webhook/inmetro"
    )
    with patch.object(_job, "_notification_hub_inmetro_base", return_value=hub_base):
        response = MagicMock()
        response.raise_for_status.return_value = None
        _job.requests.post.return_value = response

        _job.notify_on_breach(
            "prospect_waiting_conversion_6h",
            _defn(),
            {
                "alert_name": "prospect_waiting_conversion_6h",
                "id_column": "id_entity",
                "violation_count": 3,
                "threshold": "0",
                "is_breach": True,
            },
            2,
            ["p1", "p2"],
            {"p1": None, "p2": None},
            _TS,
            "enrich_agents_alerts",
            "forno",
        )

    url = _job.requests.post.call_args.args[0]
    payload = _job.requests.post.call_args.kwargs["json"]
    assert url.endswith("?space=agents-data-alarms")
    assert payload["suite_name"] == "prospect_waiting_conversion_6h"
    assert payload["status"] == "ERROR"
    assert "p1" in payload["message"] and "p2" in payload["message"]


# --- Threshold / breach decision ---


@pytest.mark.parametrize(
    "raw,expected",
    [(0, 0), (5, 5), ("3", 3), ("2.5", 2.5), (1.5, 1.5)],
)
def test_numeric_threshold_parses_registry_values(raw, expected):
    assert _job._numeric_threshold(raw) == expected


@pytest.mark.parametrize("raw", [True, False, "not-a-number"])
def test_numeric_threshold_rejects_non_numeric(raw):
    with pytest.raises(ValueError):
        _job._numeric_threshold(raw)


@pytest.mark.parametrize(
    "count,threshold,is_breach",
    [(0, 0, False), (1, 0, True), (5, 5, False), (6, 5, True)],
)
def test_evaluate_alert_breach_is_strictly_greater_than_threshold(
    count, threshold, is_breach
):
    df = MagicMock()
    df.count.return_value = count
    with patch.object(_job, "_criteria_violations_dataframe", return_value=df):
        result = _job.evaluate_alert("a", _defn(threshold=threshold), _TS)
    assert result["violation_count"] == count
    assert result["is_breach"] is is_breach


def test_evaluate_alert_returns_none_on_invalid_threshold():
    with patch.object(_job, "_criteria_violations_dataframe") as criteria:
        result = _job.evaluate_alert("a", _defn(threshold="not-a-number"), _TS)
    assert result is None
    criteria.assert_not_called()  # bail out before touching Spark


def test_evaluate_alert_returns_none_when_criteria_sql_raises():
    with patch.object(
        _job, "_criteria_violations_dataframe", side_effect=RuntimeError("bad sql")
    ):
        assert _job.evaluate_alert("a", _defn(), _TS) is None


# --- Notification Hub: URL, space, failure/fallback ---


@pytest.mark.parametrize(
    "base,expected",
    [
        ("http://hub/inmetro", "http://hub/inmetro?space=s"),
        ("http://hub/inmetro?foo=1", "http://hub/inmetro?foo=1&space=s"),
        ("http://hub/inmetro/", "http://hub/inmetro?space=s"),
    ],
)
def test_notification_hub_webhook_url_picks_right_separator(base, expected):
    assert _job._notification_hub_webhook_url(base, "s") == expected


@pytest.mark.parametrize(
    "channel,expected",
    [
        ("#agents-data-alarms", "agents-data-alarms"),
        ("alerts_agent_accreditation", "alerts_agent_accreditation"),
        ("", None),
    ],
)
def test_hub_space_from_channel(channel, expected):
    assert _job._hub_space_from_channel(channel) == expected


def test_notification_hub_base_falls_back_to_configuration_service():
    _job.DAGPackagesPathService.get_config_file_content_in_spark_jobs.side_effect = (
        FileNotFoundError
    )
    _job.ConfigurationService.return_value.get_config.return_value = (
        "http://from-config"
    )
    assert (
        _job._notification_hub_inmetro_base("enrich_agents_alerts", "forno")
        == "http://from-config"
    )


def test_post_notification_hub_returns_false_when_request_raises():
    _job.requests.post.side_effect = RuntimeError("connection reset")
    assert _job._post_notification_hub("http://hub", {"a": 1}) is False


def test_post_notification_hub_returns_false_on_http_error_status():
    response = MagicMock()
    response.raise_for_status.side_effect = RuntimeError("500")
    _job.requests.post.return_value = response
    assert _job._post_notification_hub("http://hub", {}) is False


def test_notify_on_breach_returns_false_when_base_url_missing():
    with patch.object(_job, "_notification_hub_inmetro_base", return_value=None):
        result = _job.notify_on_breach(
            "a",
            _defn(),
            {"violation_count": 1, "threshold": "0", "id_column": "id_entity"},
            1,
            ["p1"],
            {"p1": None},
            _TS,
            "enrich_agents_alerts",
            "forno",
        )
    assert result is False
    _job.requests.post.assert_not_called()


def test_notify_on_breach_returns_false_when_delivery_fails():
    with (
        patch.object(_job, "_notification_hub_inmetro_base", return_value="http://hub"),
        patch.object(_job, "_post_notification_hub", return_value=False),
    ):
        result = _job.notify_on_breach(
            "a",
            _defn(),
            {"violation_count": 1, "threshold": "0", "id_column": "id_entity"},
            1,
            ["p1"],
            {"p1": None},
            _TS,
            "enrich_agents_alerts",
            "forno",
        )
    assert result is False


# --- Main flow (Spark path) ---


def test_main_skips_hub_when_all_violating_ids_already_recorded_today(mock_spark):
    _job.DAGPackagesPathService.get_config_file_content_in_spark_jobs.return_value = (
        _VALID_REGISTRY_YAML
    )
    mock_spark.catalog.tableExists.return_value = True

    # 2 violations, but the left-anti join against already-recorded ids yields 0 new.
    violations = _violations_df_mock(count=2, anti_join_new_count=0)

    def _side_effect(query):
        if "id_alert" in query and _job.TABLE_NAME in query:
            existing = MagicMock(name="existing_ids")
            existing.select.return_value = existing
            return existing
        return violations

    mock_spark.sql.side_effect = _side_effect

    with _patch_args(), patch.object(_job, "notify_on_breach") as notify:
        _job.main()

    notify.assert_not_called()
    _job.DeltaLoader.return_value.load_table.assert_called_once()


def test_main_notifies_hub_only_for_new_entity_ids(mock_spark):
    _job.DAGPackagesPathService.get_config_file_content_in_spark_jobs.return_value = (
        _VALID_REGISTRY_YAML
    )
    evaluation = {
        "alert_name": "prospect_waiting_conversion_6h",
        "criteria_version": "abc",
        "id_column": "id_prospect_agent",
        "violations_df": MagicMock(),
        "violation_count": 2,
        "threshold": "0",
        "is_breach": True,
    }
    results_df = MagicMock()
    existing_df = MagicMock()
    new_df = MagicMock()
    results_df.join.return_value = new_df

    with (
        _patch_args(),
        patch.object(_job, "evaluate_alert", return_value=evaluation),
        patch.object(_job, "_violations_to_results_df", return_value=results_df),
        patch.object(_job, "_existing_alert_ids_df", return_value=existing_df),
        patch.object(_job, "_notify_sample", return_value=(1, ["p2"], {"p2": None})),
        patch.object(_job, "notify_on_breach") as notify,
    ):
        _job.main()

    notify.assert_called_once()
    assert notify.call_args.args[3] == 1
    assert notify.call_args.args[4] == ["p2"]


def test_main_still_writes_empty_delta_when_no_alert_is_due(mock_spark):
    _job.DAGPackagesPathService.get_config_file_content_in_spark_jobs.return_value = (
        _VALID_REGISTRY_YAML
    )
    with (
        _patch_args(logical_ts="2026-07-07T03:00:00"),
        patch.object(_job, "notify_on_breach"),
    ):
        _job.main()

    mock_spark.createDataFrame.assert_called()
    _job.DeltaLoader.return_value.load_table.assert_called_once()


def test_main_continues_when_one_alert_sql_fails(mock_spark):
    yaml_two = """
alerts:
  ok:
    description: ok
    channel: "#agents-data-alarms"
    cron: "0 */2 * * *"
    threshold: 0
    severity: Error
    id_column: id_ok
    criteria_sql: SELECT ok_marker
  bad:
    description: bad
    channel: "#agents-data-alarms"
    cron: "0 */2 * * *"
    threshold: 0
    severity: Error
    id_column: id_bad
    criteria_sql: SELECT bad_marker
"""
    _job.DAGPackagesPathService.get_config_file_content_in_spark_jobs.return_value = (
        yaml_two
    )

    ok_df = _violations_df_mock(
        count=1, sample_rows=[_row(id_entity="ok1", entity_value=None)]
    )

    def _side_effect(query):
        if "bad_marker" in query:
            raise RuntimeError("sql fail")
        mock_spark.sql.return_value = ok_df
        return ok_df

    mock_spark.sql.side_effect = _side_effect

    with _patch_args(), patch.object(_job, "notify_on_breach"):
        _job.main()

    assert mock_spark.sql.call_count >= 2
