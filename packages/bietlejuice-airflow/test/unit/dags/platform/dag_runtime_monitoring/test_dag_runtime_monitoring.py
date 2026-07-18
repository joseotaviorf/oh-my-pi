"""Unit tests for the platform dag_runtime_monitoring DAG logic and structure."""

import json
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest import mock

import pytest

from dags.platform.dag_runtime_monitoring.dag_runtime_monitoring import (
    _HISTORY_QUERY,
    _RUNNING_QUERY,
    DAG_ID,
    DEDUP_VARIABLE_KEY,
    JIRA_OPS_VARIABLE,
    _as_str_list,
    _build_alert_text,
    _entry_from_finding,
    _evaluate_all,
    _evaluate_runtime,
    _failed_text,
    _fetch_run_states,
    _format_duration,
    _initial_text,
    _load_dedup_state,
    _normalize_ledger,
    _parse_test_options,
    _percentile,
    _post_gchat,
    _resolve_config,
    _resolved_text,
    _synthetic_findings,
    _update_text,
    dag,
    monitor_dag_runtimes,
)

_MODULE = "dags.platform.dag_runtime_monitoring.dag_runtime_monitoring"

_WEBHOOK_KEY = "GCHAT_DAG_RUNTIME_MONITORING_WEBHOOK"
_WEBHOOK_URL = "https://chat.example.com/hook?key=k&token=t"
_CRITICAL_DAG = "bietlejuice.ebdb_location"
_STANDARD_DAG = "bietlejuice.some_small_dag"

_CONFIG = {
    "critical_dags": [_CRITICAL_DAG],
    "lookback_days": 7,
    "min_history_runs": 3,
    "percentile": 90,
    "factor": 1.1,
    # Floor disabled in the shared fixture; exercised explicitly in dedicated tests.
    "min_alert_duration_minutes": 0,
}


# --------------------------------------------------------------------------- #
# Pure helpers
# --------------------------------------------------------------------------- #
class TestPercentile:
    def test_single_value(self):
        assert _percentile([42.0], 90) == 42.0

    def test_p90_of_uniform(self):
        assert _percentile([600.0] * 10, 90) == 600.0

    def test_p90_interpolation(self):
        assert _percentile(list(range(11)), 90) == 9.0

    def test_empty_raises(self):
        with pytest.raises(ValueError):
            _percentile([], 90)


class TestEvaluateRuntime:
    def test_none_when_insufficient_history(self):
        assert (
            _evaluate_runtime(9999, [600] * 4, percentile=90, factor=1.1, min_history=5)
            is None
        )

    def test_none_when_within_threshold(self):
        assert (
            _evaluate_runtime(650, [600] * 10, percentile=90, factor=1.1, min_history=5)
            is None
        )

    def test_finding_when_over_threshold(self):
        result = _evaluate_runtime(
            1200, [600] * 10, percentile=90, factor=1.1, min_history=5
        )
        assert result is not None
        assert result["baseline_s"] == 600.0
        assert result["threshold_s"] == pytest.approx(660.0)
        assert result["pct_over"] == 100

    def test_none_when_baseline_is_zero(self):
        assert (
            _evaluate_runtime(120, [0] * 10, percentile=90, factor=1.1, min_history=5)
            is None
        )

    def test_none_when_below_min_elapsed_floor(self):
        assert (
            _evaluate_runtime(
                1200,
                [600] * 10,
                percentile=90,
                factor=1.1,
                min_history=5,
                min_elapsed_s=3600,
            )
            is None
        )

    def test_finding_when_above_min_elapsed_floor(self):
        result = _evaluate_runtime(
            5400,
            [600] * 10,
            percentile=90,
            factor=1.1,
            min_history=5,
            min_elapsed_s=3600,
        )
        assert result is not None
        assert result["elapsed_s"] == 5400.0


class TestFormatDuration:
    @pytest.mark.parametrize(
        "seconds,expected",
        [(45, "45s"), (150, "2m30s"), (3600, "1h00m"), (5400, "1h30m")],
    )
    def test_format(self, seconds, expected):
        assert _format_duration(seconds) == expected


class TestResolveConfig:
    def test_defaults_applied_when_missing(self):
        merged = _resolve_config({"critical_dags": ["a"]})
        assert merged["critical_dags"] == ["a"]
        assert merged["percentile"] == 90
        assert merged["min_history_runs"] == 3
        assert merged["lookback_days"] == 7
        assert merged["min_alert_duration_minutes"] == 60

    def test_none_uses_all_defaults(self):
        assert _resolve_config(None)["critical_dags"] == []


class TestEvaluateAll:
    def test_assigns_tier_and_skips_normal_runs(self):
        now = datetime(2026, 7, 16, 12, 0, tzinfo=timezone.utc)
        running = [
            SimpleNamespace(
                dag_id=_CRITICAL_DAG,
                run_id="r1",
                start_date=now - timedelta(minutes=60),
            ),
            SimpleNamespace(
                dag_id=_STANDARD_DAG,
                run_id="r2",
                start_date=now - timedelta(minutes=60),
            ),
            SimpleNamespace(
                dag_id="bietlejuice.fast_dag",
                run_id="r3",
                start_date=now - timedelta(seconds=30),
            ),
        ]
        durations = {
            _CRITICAL_DAG: [600.0] * 10,
            _STANDARD_DAG: [600.0] * 10,
            "bietlejuice.fast_dag": [600.0] * 10,
        }
        by_dag = {
            f["dag_id"]: f for f in _evaluate_all(running, durations, now, _CONFIG)
        }
        assert by_dag[_CRITICAL_DAG]["tier"] == "critical"
        assert by_dag[_STANDARD_DAG]["tier"] == "standard"
        assert "bietlejuice.fast_dag" not in by_dag

    def test_skips_when_no_history(self):
        now = datetime(2026, 7, 16, 12, 0, tzinfo=timezone.utc)
        running = [
            SimpleNamespace(
                dag_id=_STANDARD_DAG, run_id="r2", start_date=now - timedelta(hours=5)
            )
        ]
        assert _evaluate_all(running, {}, now, _CONFIG) == []

    def test_honors_min_alert_duration_floor(self):
        config = {**_CONFIG, "min_alert_duration_minutes": 60}
        now = datetime(2026, 7, 16, 12, 0, tzinfo=timezone.utc)
        running = [
            SimpleNamespace(
                dag_id=_CRITICAL_DAG,
                run_id="short",
                start_date=now - timedelta(minutes=20),
            ),
            SimpleNamespace(
                dag_id=_STANDARD_DAG,
                run_id="long",
                start_date=now - timedelta(minutes=90),
            ),
        ]
        durations = {_CRITICAL_DAG: [600.0] * 10, _STANDARD_DAG: [600.0] * 10}
        by_dag = {
            f["dag_id"]: f for f in _evaluate_all(running, durations, now, config)
        }
        assert _CRITICAL_DAG not in by_dag
        assert _STANDARD_DAG in by_dag


def test_build_alert_text_contains_key_facts():
    finding = {
        "dag_id": _CRITICAL_DAG,
        "run_id": "r1",
        "elapsed_s": 3600,
        "baseline_s": 600,
        "history_count": 10,
        "percentile": 90,
        "pct_over": 500,
    }
    text = _build_alert_text(finding)
    assert _CRITICAL_DAG in text
    assert "P90" in text
    assert "500% over baseline" in text
    assert "r1" in text


# --------------------------------------------------------------------------- #
# Message builders + ledger helpers
# --------------------------------------------------------------------------- #
_ENTRY = {
    "dag_id": _STANDARD_DAG,
    "run_id": "r2",
    "tier": "standard",
    "first_alert_ts": "2026-07-17T18:00:00+00:00",
    "baseline_s": 1500.0,
    "threshold_s": 2250.0,
    "percentile": 90,
    "history_count": 7,
}


def test_message_builders():
    assert "running slower than usual" in _initial_text(_ENTRY, 3600)
    assert "P90 baseline" in _initial_text(_ENTRY, 3600)
    assert "still running" in _update_text(_ENTRY, 5400)
    assert "finished after" in _resolved_text(_ENTRY, 3600)
    assert "FAILED" in _failed_text(_ENTRY, 3600)
    assert _STANDARD_DAG in _resolved_text(_ENTRY, 3600)


def test_message_builders_without_baseline():
    # Back-compat entry (old ledger) has no baseline_s → messages omit the % detail.
    entry = {"dag_id": _STANDARD_DAG, "run_id": "r2", "tier": "standard"}
    assert "baseline unavailable" in _initial_text(entry, 3600)
    assert "unknown time" in _resolved_text(entry, None)


class TestNormalizeLedger:
    def test_dict_entries_preserved(self):
        raw = {"k": {"dag_id": "d", "run_id": "r", "tier": "standard"}}
        assert _normalize_ledger(raw)["k"]["tier"] == "standard"

    def test_old_string_entry_upgraded_as_standard(self):
        raw = {"bietlejuice.x|run_1": "2026-07-17T18:00:00+00:00"}
        entry = _normalize_ledger(raw)["bietlejuice.x|run_1"]
        assert entry["dag_id"] == "bietlejuice.x"
        assert entry["run_id"] == "run_1"
        assert entry["tier"] == "standard"

    def test_old_string_entry_critical_dag_keeps_jira_tier(self):
        # Pre-change dedup recorded both tiers as bare timestamps; resolve tier from
        # critical_dags so deploy does not route in-flight critical runs to gchat.
        raw = {f"{_CRITICAL_DAG}|r1": "2026-07-17T18:00:00+00:00"}
        entry = _normalize_ledger(raw, critical_dags=[_CRITICAL_DAG])[
            f"{_CRITICAL_DAG}|r1"
        ]
        assert entry["tier"] == "critical"
        assert entry["dag_id"] == _CRITICAL_DAG
        assert entry["run_id"] == "r1"

    @pytest.mark.parametrize(
        "value",
        [
            {},
            {"tier": "standard"},
            {"baseline_s": 1500.0},
        ],
    )
    def test_partial_dict_fills_dag_id_and_run_id_from_key(self, value):
        # Operator-edited / truncated Variable JSON must not KeyError in _fetch_run_states.
        key = "bietlejuice.x|run_1"
        entry = _normalize_ledger({key: value})[key]
        assert entry["dag_id"] == "bietlejuice.x"
        assert entry["run_id"] == "run_1"
        assert entry["tier"] == "standard"
        # Existing fields are kept.
        for field, expected in value.items():
            assert entry[field] == expected

    def test_partial_dict_critical_tier_from_key(self):
        key = f"{_CRITICAL_DAG}|r1"
        entry = _normalize_ledger({key: {}}, critical_dags=[_CRITICAL_DAG])[key]
        assert entry["dag_id"] == _CRITICAL_DAG
        assert entry["run_id"] == "r1"
        assert entry["tier"] == "critical"


# --------------------------------------------------------------------------- #
# DAG structure + queries
# --------------------------------------------------------------------------- #
def test_dag_schedule_and_id():
    assert dag.dag_id == DAG_ID
    assert dag.schedule_interval == "*/30 * * * *"


@pytest.mark.parametrize("query", [_RUNNING_QUERY, _HISTORY_QUERY])
def test_queries_exclude_test_runs(query):
    sql = str(query)
    assert "run_type" in sql
    assert "scheduled" in sql
    assert "dataset_triggered" in sql
    assert "mediator_trig" in sql


class TestFetchRunStates:
    def test_filters_to_exact_pairs(self):
        entries = [
            {"dag_id": "bietlejuice.a", "run_id": "r1"},
            {"dag_id": "bietlejuice.b", "run_id": "r2"},
        ]
        rows = [
            SimpleNamespace(
                dag_id="bietlejuice.a",
                run_id="r1",
                state="running",
                start_date=None,
                end_date=None,
            ),
            SimpleNamespace(
                dag_id="bietlejuice.b",
                run_id="r2",
                state="success",
                start_date=None,
                end_date=None,
            ),
            # over-match from the IN×IN cross product — must be dropped
            SimpleNamespace(
                dag_id="bietlejuice.a",
                run_id="r2",
                state="failed",
                start_date=None,
                end_date=None,
            ),
        ]
        session = mock.MagicMock()
        session.execute.return_value.fetchall.return_value = rows
        states = _fetch_run_states(session, entries)
        assert set(states) == {("bietlejuice.a", "r1"), ("bietlejuice.b", "r2")}

    def test_empty_entries_no_query(self):
        session = mock.MagicMock()
        assert _fetch_run_states(session, []) == {}
        session.execute.assert_not_called()


# --------------------------------------------------------------------------- #
# _post_gchat (threaded webhook post)
# --------------------------------------------------------------------------- #
class TestPostGchat:
    @mock.patch(f"{_MODULE}.requests")
    def test_posts_threaded_payload(self, mock_requests):
        mock_requests.post.return_value = mock.MagicMock()
        assert _post_gchat(_WEBHOOK_URL, "hello", "rubinho::x|r1") is True
        url = mock_requests.post.call_args.args[0]
        payload = mock_requests.post.call_args.kwargs["json"]
        assert "messageReplyOption=REPLY_MESSAGE_FALLBACK_TO_NEW_THREAD" in url
        assert payload["text"] == "hello"
        assert payload["thread"]["threadKey"] == "rubinho::x|r1"

    @mock.patch(f"{_MODULE}.requests")
    def test_returns_false_on_error(self, mock_requests):
        mock_requests.post.return_value.raise_for_status.side_effect = Exception("500")
        assert _post_gchat(_WEBHOOK_URL, "hi", "k") is False

    def test_no_webhook_returns_false(self):
        assert _post_gchat(None, "hi", "k") is False


# --------------------------------------------------------------------------- #
# Orchestration / lifecycle
# --------------------------------------------------------------------------- #
def _variable_get_factory(environment="prod", ledger="{}"):
    def _get(key, default_var=None):
        if key == _WEBHOOK_KEY:
            return _WEBHOOK_URL
        if key == "environment":
            return environment
        if key == DEDUP_VARIABLE_KEY:
            return ledger
        if key == JIRA_OPS_VARIABLE:
            return json.dumps({"username": "u", "token": "t", "cloud_id": "c"})
        return default_var

    return _get


def _config_get(key):
    if key == "notification_webhooks_keys":
        return {"dag_runtime_monitoring": _WEBHOOK_KEY}
    return dict(_CONFIG)


def _running_row(dag_id, run_id, minutes_ago, now):
    return SimpleNamespace(
        dag_id=dag_id, run_id=run_id, start_date=now - timedelta(minutes=minutes_ago)
    )


def _saved_ledger(mock_var):
    return json.loads(mock_var.set.call_args.args[1])


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}._fetch_run_states", return_value={})
@mock.patch(f"{_MODULE}._fetch_recent_durations")
@mock.patch(f"{_MODULE}._fetch_running_runs")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_new_standard_anomaly_posts_initial_and_tracks(
    mock_cfg, mock_var, mock_running, mock_durations, mock_states, mock_jira, mock_post
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()
    now = datetime.now(timezone.utc)
    mock_running.return_value = [_running_row(_STANDARD_DAG, "r2", 90, now)]
    mock_durations.return_value = {_STANDARD_DAG: [600.0] * 10}

    monitor_dag_runtimes(session=mock.MagicMock())

    mock_jira.assert_not_called()
    mock_post.assert_called_once()
    text_arg = mock_post.call_args.args[1]
    assert "running slower than usual" in text_arg
    saved = _saved_ledger(mock_var)
    assert saved[f"{_STANDARD_DAG}|r2"]["tier"] == "standard"
    assert saved[f"{_STANDARD_DAG}|r2"]["baseline_s"] == 600.0


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}._fetch_run_states", return_value={})
@mock.patch(f"{_MODULE}._fetch_recent_durations")
@mock.patch(f"{_MODULE}._fetch_running_runs")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_new_critical_anomaly_pages_jira_once(
    mock_cfg, mock_var, mock_running, mock_durations, mock_states, mock_jira, mock_post
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()
    now = datetime.now(timezone.utc)
    mock_running.return_value = [_running_row(_CRITICAL_DAG, "r1", 90, now)]
    mock_durations.return_value = {_CRITICAL_DAG: [600.0] * 10}

    monitor_dag_runtimes(session=mock.MagicMock())

    mock_jira.assert_called_once()
    mock_post.assert_not_called()  # critical → JiraOps only, no gchat
    saved = _saved_ledger(mock_var)
    assert saved[f"{_CRITICAL_DAG}|r1"]["tier"] == "critical"


def _lifecycle_patches(func):
    for dec in reversed(
        [
            mock.patch(f"{_MODULE}.ConfigurationService"),
            mock.patch(f"{_MODULE}.Variable"),
            mock.patch(f"{_MODULE}._fetch_running_runs", return_value=[]),
            mock.patch(f"{_MODULE}._fetch_run_states"),
            mock.patch(f"{_MODULE}._post_gchat", return_value=True),
        ]
    ):
        func = dec(func)
    return func


@_lifecycle_patches
def test_tracked_running_gets_update(
    mock_post, mock_states, mock_running, mock_var, mock_cfg
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    ledger = {f"{_STANDARD_DAG}|r2": dict(_ENTRY)}
    mock_var.get.side_effect = _variable_get_factory(ledger=json.dumps(ledger))
    now = datetime.now(timezone.utc)
    mock_states.return_value = {
        (_STANDARD_DAG, "r2"): SimpleNamespace(
            dag_id=_STANDARD_DAG,
            run_id="r2",
            state="running",
            start_date=now - timedelta(hours=2),
            end_date=None,
        )
    }

    monitor_dag_runtimes(session=mock.MagicMock())

    mock_post.assert_called_once()
    assert "still running" in mock_post.call_args.args[1]
    assert f"{_STANDARD_DAG}|r2" in _saved_ledger(mock_var)  # kept


@_lifecycle_patches
def test_tracked_success_posts_resolved_and_drops(
    mock_post, mock_states, mock_running, mock_var, mock_cfg
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    ledger = {f"{_STANDARD_DAG}|r2": dict(_ENTRY)}
    mock_var.get.side_effect = _variable_get_factory(ledger=json.dumps(ledger))
    now = datetime.now(timezone.utc)
    mock_states.return_value = {
        (_STANDARD_DAG, "r2"): SimpleNamespace(
            dag_id=_STANDARD_DAG,
            run_id="r2",
            state="success",
            start_date=now - timedelta(hours=2),
            end_date=now,
        )
    }

    monitor_dag_runtimes(session=mock.MagicMock())

    assert "finished after" in mock_post.call_args.args[1]
    assert f"{_STANDARD_DAG}|r2" not in _saved_ledger(mock_var)  # dropped


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}._fetch_run_states")
@mock.patch(f"{_MODULE}._fetch_recent_durations")
@mock.patch(f"{_MODULE}._fetch_running_runs")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_closed_tracked_run_not_reopened_from_stale_finding(
    mock_cfg, mock_var, mock_running, mock_durations, mock_states, mock_jira, mock_post
):
    # Race: findings from the running snapshot still list a run that follow-up just
    # closed and dropped from the ledger — must not open a fresh incident same cycle.
    mock_cfg.return_value.get_config.side_effect = _config_get
    ledger = {f"{_STANDARD_DAG}|r2": dict(_ENTRY)}
    mock_var.get.side_effect = _variable_get_factory(ledger=json.dumps(ledger))
    now = datetime.now(timezone.utc)
    mock_running.return_value = [_running_row(_STANDARD_DAG, "r2", 90, now)]
    mock_durations.return_value = {_STANDARD_DAG: [600.0] * 10}
    mock_states.return_value = {
        (_STANDARD_DAG, "r2"): SimpleNamespace(
            dag_id=_STANDARD_DAG,
            run_id="r2",
            state="success",
            start_date=now - timedelta(hours=2),
            end_date=now,
        )
    }

    monitor_dag_runtimes(session=mock.MagicMock())

    mock_jira.assert_not_called()
    mock_post.assert_called_once()
    assert "finished after" in mock_post.call_args.args[1]
    assert "running slower than usual" not in mock_post.call_args.args[1]
    assert f"{_STANDARD_DAG}|r2" not in _saved_ledger(mock_var)


@_lifecycle_patches
def test_tracked_failed_posts_failure_and_drops(
    mock_post, mock_states, mock_running, mock_var, mock_cfg
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    ledger = {f"{_STANDARD_DAG}|r2": dict(_ENTRY)}
    mock_var.get.side_effect = _variable_get_factory(ledger=json.dumps(ledger))
    now = datetime.now(timezone.utc)
    mock_states.return_value = {
        (_STANDARD_DAG, "r2"): SimpleNamespace(
            dag_id=_STANDARD_DAG,
            run_id="r2",
            state="failed",
            start_date=now - timedelta(hours=2),
            end_date=now,
        )
    }

    monitor_dag_runtimes(session=mock.MagicMock())

    assert "FAILED" in mock_post.call_args.args[1]
    assert f"{_STANDARD_DAG}|r2" not in _saved_ledger(mock_var)


@_lifecycle_patches
def test_tracked_terminal_keeps_ledger_when_closing_post_fails(
    mock_post, mock_states, mock_running, mock_var, mock_cfg
):
    # Closing delivery must succeed before drop — same gate as initial alerts.
    mock_post.return_value = False
    mock_cfg.return_value.get_config.side_effect = _config_get
    ledger = {f"{_STANDARD_DAG}|r2": dict(_ENTRY)}
    mock_var.get.side_effect = _variable_get_factory(ledger=json.dumps(ledger))
    now = datetime.now(timezone.utc)
    mock_states.return_value = {
        (_STANDARD_DAG, "r2"): SimpleNamespace(
            dag_id=_STANDARD_DAG,
            run_id="r2",
            state="success",
            start_date=now - timedelta(hours=2),
            end_date=now,
        )
    }

    monitor_dag_runtimes(session=mock.MagicMock())

    assert "finished after" in mock_post.call_args.args[1]
    assert f"{_STANDARD_DAG}|r2" in _saved_ledger(mock_var)  # retried next cycle


@_lifecycle_patches
def test_tracked_critical_terminal_drops_silently(
    mock_post, mock_states, mock_running, mock_var, mock_cfg
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    entry = {**_ENTRY, "dag_id": _CRITICAL_DAG, "run_id": "r1", "tier": "critical"}
    ledger = {f"{_CRITICAL_DAG}|r1": entry}
    mock_var.get.side_effect = _variable_get_factory(ledger=json.dumps(ledger))
    now = datetime.now(timezone.utc)
    mock_states.return_value = {
        (_CRITICAL_DAG, "r1"): SimpleNamespace(
            dag_id=_CRITICAL_DAG,
            run_id="r1",
            state="success",
            start_date=now - timedelta(hours=2),
            end_date=now,
        )
    }

    monitor_dag_runtimes(session=mock.MagicMock())

    mock_post.assert_not_called()  # critical closes in Jira, no gchat
    assert f"{_CRITICAL_DAG}|r1" not in _saved_ledger(mock_var)


@_lifecycle_patches
def test_old_ledger_critical_string_does_not_get_gchat(
    mock_post, mock_states, mock_running, mock_var, mock_cfg
):
    # Old Variable format: bare timestamp for both tiers. Must not treat critical as
    # standard and spam threaded gchat updates/closures after deploy.
    mock_cfg.return_value.get_config.side_effect = _config_get
    ledger = {f"{_CRITICAL_DAG}|r1": "2026-07-17T18:00:00+00:00"}
    mock_var.get.side_effect = _variable_get_factory(ledger=json.dumps(ledger))
    now = datetime.now(timezone.utc)
    mock_states.return_value = {
        (_CRITICAL_DAG, "r1"): SimpleNamespace(
            dag_id=_CRITICAL_DAG,
            run_id="r1",
            state="running",
            start_date=now - timedelta(hours=2),
            end_date=None,
        )
    }

    monitor_dag_runtimes(session=mock.MagicMock())

    mock_post.assert_not_called()
    saved = _saved_ledger(mock_var)
    assert saved[f"{_CRITICAL_DAG}|r1"]["tier"] == "critical"


@_lifecycle_patches
def test_tracked_run_vanished_is_dropped(
    mock_post, mock_states, mock_running, mock_var, mock_cfg
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    ledger = {f"{_STANDARD_DAG}|r2": dict(_ENTRY)}
    mock_var.get.side_effect = _variable_get_factory(ledger=json.dumps(ledger))
    mock_states.return_value = {}  # run row no longer present

    monitor_dag_runtimes(session=mock.MagicMock())

    mock_post.assert_not_called()
    assert _saved_ledger(mock_var) == {}


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}._fetch_run_states", return_value={})
@mock.patch(f"{_MODULE}._fetch_recent_durations")
@mock.patch(f"{_MODULE}._fetch_running_runs")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_non_prod_does_not_send_or_track(
    mock_cfg, mock_var, mock_running, mock_durations, mock_states, mock_jira, mock_post
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory(environment="forno")
    now = datetime.now(timezone.utc)
    mock_running.return_value = [_running_row(_STANDARD_DAG, "r2", 90, now)]
    mock_durations.return_value = {_STANDARD_DAG: [600.0] * 10}

    monitor_dag_runtimes(session=mock.MagicMock())

    mock_jira.assert_not_called()
    mock_post.assert_not_called()
    mock_var.set.assert_not_called()


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}._fetch_run_states", return_value={})
@mock.patch(f"{_MODULE}._fetch_recent_durations")
@mock.patch(f"{_MODULE}._fetch_running_runs")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_only_dags_filters_evaluated_runs(
    mock_cfg, mock_var, mock_running, mock_durations, mock_states, mock_jira, mock_post
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()
    now = datetime.now(timezone.utc)
    mock_running.return_value = [
        _running_row(_CRITICAL_DAG, "r1", 90, now),
        _running_row(_STANDARD_DAG, "r2", 90, now),
    ]
    mock_durations.return_value = {
        _CRITICAL_DAG: [600.0] * 10,
        _STANDARD_DAG: [600.0] * 10,
    }

    monitor_dag_runtimes(
        session=mock.MagicMock(), run_conf={"only_dags": [_STANDARD_DAG]}
    )

    mock_jira.assert_not_called()  # critical filtered out
    mock_post.assert_called_once()


# --------------------------------------------------------------------------- #
# Simulate / test mode
# --------------------------------------------------------------------------- #
@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_simulate_dry_run_sends_nothing(mock_cfg, mock_var, mock_jira, mock_post):
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()

    monitor_dag_runtimes(session=mock.MagicMock(), run_conf={"simulate": True})

    mock_jira.assert_not_called()
    mock_post.assert_not_called()
    mock_var.set.assert_not_called()


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_simulate_force_send_posts_initial_to_test_destinations(
    mock_cfg, mock_var, mock_jira, mock_post
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory(environment="forno")

    monitor_dag_runtimes(
        session=mock.MagicMock(),
        run_conf={
            "simulate": True,
            "force_send": True,
            "test_webhook": "https://chat.example.com/TEST",
            "test_responder_team_id": "test-team-123",
        },
    )

    # Critical synthetic → JiraOps test team; standard synthetic → test webhook.
    _, jira_kwargs = mock_jira.call_args
    assert jira_kwargs["responder_team_id"] == "test-team-123"
    assert jira_kwargs["test"] is True
    assert mock_post.call_args.args[0] == "https://chat.example.com/TEST"
    mock_var.set.assert_not_called()  # simulate never writes the ledger


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_force_send_critical_without_test_team_is_not_paged(
    mock_cfg, mock_var, mock_jira, mock_post
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory(environment="forno")

    monitor_dag_runtimes(
        session=mock.MagicMock(),
        run_conf={
            "simulate": True,
            "force_send": True,
            "test_webhook": "https://chat.example.com/TEST",
        },
    )

    mock_jira.assert_not_called()  # critical downgraded to log-only
    mock_post.assert_called_once()  # standard still delivered


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}._fetch_run_states", return_value={})
@mock.patch(f"{_MODULE}._fetch_running_runs", return_value=[])
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_reads_trigger_conf_from_dag_run_not_context_conf(
    mock_cfg, mock_var, mock_running, mock_states, mock_jira, mock_post
):
    # Airflow injects context["conf"] = the global config object (not a dict); the trigger
    # payload lives on dag_run.conf. Must read dag_run.conf and not choke.
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()

    class _FakeAirflowConf:
        def get(self, *a, **k):
            raise AssertionError("must not read the Airflow config object")

    dag_run = SimpleNamespace(conf={"simulate": True, "dry_run": True})
    monitor_dag_runtimes(
        session=mock.MagicMock(), conf=_FakeAirflowConf(), dag_run=dag_run
    )

    mock_jira.assert_not_called()
    mock_post.assert_not_called()
    mock_var.set.assert_not_called()


# --------------------------------------------------------------------------- #
# Conf parsing / hardening
# --------------------------------------------------------------------------- #
class TestParseTestOptions:
    def test_empty_conf_is_normal_run(self):
        assert _parse_test_options(None) == {
            "simulate": False,
            "simulate_dags": None,
            "simulate_state": None,
            "dry_run": False,
            "force_send": False,
            "test_webhook": None,
            "test_responder_team_id": None,
            "only_dags": None,
        }

    def test_simulate_defaults_dry_run_true(self):
        assert _parse_test_options({"simulate": True})["dry_run"] is True

    def test_force_send_defaults_dry_run_false(self):
        assert (
            _parse_test_options({"simulate": True, "force_send": True})["dry_run"]
            is False
        )

    def test_explicit_dry_run_wins(self):
        assert (
            _parse_test_options(
                {"simulate": True, "force_send": True, "dry_run": True}
            )["dry_run"]
            is True
        )

    def test_coerces_dag_lists(self):
        opts = _parse_test_options(
            {"only_dags": "bietlejuice.x", "simulate_dags": "bietlejuice.y"}
        )
        assert opts["only_dags"] == ["bietlejuice.x"]
        assert opts["simulate_dags"] == ["bietlejuice.y"]


class TestAsStrList:
    @pytest.mark.parametrize(
        "value,expected",
        [
            (None, None),
            ("bietlejuice.x", ["bietlejuice.x"]),
            (["a", "b"], ["a", "b"]),
            ((1, 2), ["1", "2"]),
            (5, None),
            ({"a": 1}, None),
        ],
    )
    def test_coerce(self, value, expected):
        assert _as_str_list(value) == expected


class TestLoadDedupState:
    @pytest.mark.parametrize(
        "stored", ["null", "[1, 2]", "5", '"a string"', "not-json"]
    )
    def test_non_mapping_becomes_empty_dict(self, stored):
        with mock.patch(f"{_MODULE}.Variable") as mock_var:
            mock_var.get.return_value = stored
            assert _load_dedup_state() == {}

    def test_valid_mapping_preserved(self):
        with mock.patch(f"{_MODULE}.Variable") as mock_var:
            mock_var.get.return_value = '{"a|1": {"tier": "standard"}}'
            assert _load_dedup_state() == {"a|1": {"tier": "standard"}}


def test_synthetic_findings_default_covers_both_tiers():
    findings = _synthetic_findings(_CONFIG)
    assert {f["tier"] for f in findings} == {"critical", "standard"}
    assert any(f["dag_id"] == _CRITICAL_DAG for f in findings)


def test_entry_from_finding_snapshots_baseline():
    finding = {
        "dag_id": _STANDARD_DAG,
        "run_id": "r2",
        "tier": "standard",
        "elapsed_s": 5400,
        "baseline_s": 600.0,
        "threshold_s": 660.0,
        "percentile": 90,
        "history_count": 10,
    }
    entry = _entry_from_finding(finding, first_alert_ts="ts")
    assert entry["baseline_s"] == 600.0
    assert entry["tier"] == "standard"
    assert entry["first_alert_ts"] == "ts"
