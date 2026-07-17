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
    _evaluate_all,
    _evaluate_runtime,
    _format_duration,
    _load_dedup_state,
    _parse_test_options,
    _percentile,
    _resolve_config,
    _synthetic_findings,
    dag,
    monitor_dag_runtimes,
)

_MODULE = "dags.platform.dag_runtime_monitoring.dag_runtime_monitoring"

_WEBHOOK_KEY = "GCHAT_DAG_RUNTIME_MONITORING_WEBHOOK"
_WEBHOOK_URL = "https://chat.example.com/hook"
_CRITICAL_DAG = "bietlejuice.ebdb_location"
_STANDARD_DAG = "bietlejuice.some_small_dag"

_CONFIG = {
    "critical_dags": [_CRITICAL_DAG],
    "lookback_days": 7,
    "min_history_runs": 3,
    "percentile": 90,
    "factor": 1.1,
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
        # 0..10 → P90 rank = 9.0 → exactly 9
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
        # baseline 600, threshold 660; elapsed 650 → not flagged
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
        # Recent runs all ~0s → baseline 0 → do not flag every positive elapsed time.
        assert (
            _evaluate_runtime(120, [0] * 10, percentile=90, factor=1.1, min_history=5)
            is None
        )


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

    def test_none_uses_all_defaults(self):
        merged = _resolve_config(None)
        assert merged["critical_dags"] == []


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
        findings = _evaluate_all(running, durations, now, _CONFIG)
        by_dag = {f["dag_id"]: f for f in findings}
        assert by_dag[_CRITICAL_DAG]["tier"] == "critical"
        assert by_dag[_STANDARD_DAG]["tier"] == "standard"
        assert "bietlejuice.fast_dag" not in by_dag  # within baseline → not flagged

    def test_skips_when_no_history(self):
        now = datetime(2026, 7, 16, 12, 0, tzinfo=timezone.utc)
        running = [
            SimpleNamespace(
                dag_id=_STANDARD_DAG, run_id="r2", start_date=now - timedelta(hours=5)
            )
        ]
        assert _evaluate_all(running, {}, now, _CONFIG) == []


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
# DAG structure
# --------------------------------------------------------------------------- #
def test_dag_schedule_and_id():
    assert dag.dag_id == DAG_ID
    assert dag.schedule_interval == "*/30 * * * *"


@pytest.mark.parametrize("query", [_RUNNING_QUERY, _HISTORY_QUERY])
def test_queries_exclude_test_runs(query):
    sql = str(query)
    # Real automatic runs only — manual/backfill (TEST_RUN) are excluded from both
    # alerting and the baseline.
    assert "run_type" in sql
    assert "scheduled" in sql
    assert "dataset_triggered" in sql
    assert "mediator_trig" in sql


# --------------------------------------------------------------------------- #
# Orchestration / routing
# --------------------------------------------------------------------------- #
def _running_and_history_results(now):
    running = mock.MagicMock()
    running.fetchall.return_value = [
        SimpleNamespace(
            dag_id=_CRITICAL_DAG, run_id="r1", start_date=now - timedelta(minutes=60)
        ),
        SimpleNamespace(
            dag_id=_STANDARD_DAG, run_id="r2", start_date=now - timedelta(minutes=60)
        ),
    ]
    history = mock.MagicMock()
    history.fetchall.return_value = [
        SimpleNamespace(dag_id=_CRITICAL_DAG, duration_s=600.0) for _ in range(10)
    ] + [SimpleNamespace(dag_id=_STANDARD_DAG, duration_s=600.0) for _ in range(10)]
    return running, history


def _variable_get_factory(environment="prod", dedup_state="{}"):
    def _get(key, default_var=None):
        if key == _WEBHOOK_KEY:
            return _WEBHOOK_URL
        if key == "environment":
            return environment
        if key == DEDUP_VARIABLE_KEY:
            return dedup_state
        if key == JIRA_OPS_VARIABLE:
            return json.dumps({"username": "u", "token": "t", "cloud_id": "c"})
        return default_var

    return _get


def _config_get(key):
    if key == "notification_webhooks_keys":
        return {"dag_runtime_monitoring": _WEBHOOK_KEY}
    return dict(_CONFIG)


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_routes_critical_to_jira_and_standard_to_gchat(
    mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat
):
    mock_cfg_cls.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()
    mock_jira_cls.return_value.create_alert.return_value = mock.MagicMock()
    mock_gchat.send_message.return_value = True

    now = datetime.now(timezone.utc)
    running, history = _running_and_history_results(now)
    session = mock.MagicMock()
    session.execute.side_effect = [running, history]

    monitor_dag_runtimes(session=session)

    # One JiraOps alert for the critical DAG.
    mock_jira_cls.return_value.create_alert.assert_called_once()
    _, jira_kwargs = mock_jira_cls.return_value.create_alert.call_args
    assert jira_kwargs["extra_properties"]["DAG"] == _CRITICAL_DAG
    assert jira_kwargs["alias"] == f"dag-runtime-{_CRITICAL_DAG}-r1"

    # One batched gchat message for the standard DAG.
    mock_gchat.send_message.assert_called_once()
    sent_message = mock_gchat.send_message.call_args.args[0]
    assert _STANDARD_DAG in sent_message.content
    assert sent_message.destination == _WEBHOOK_URL

    # Dedup state persisted for both alerted runs.
    mock_var.set.assert_called_once()
    saved = json.loads(mock_var.set.call_args.args[1])
    assert f"{_CRITICAL_DAG}|r1" in saved
    assert f"{_STANDARD_DAG}|r2" in saved


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_dedup_skips_already_alerted_run(
    mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat
):
    mock_cfg_cls.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory(
        dedup_state=json.dumps({f"{_CRITICAL_DAG}|r1": "2026-07-16T11:00:00+00:00"})
    )
    mock_gchat.send_message.return_value = True

    now = datetime.now(timezone.utc)
    running, history = _running_and_history_results(now)
    session = mock.MagicMock()
    session.execute.side_effect = [running, history]

    monitor_dag_runtimes(session=session)

    # Critical run r1 already alerted → no new JiraOps alert.
    mock_jira_cls.return_value.create_alert.assert_not_called()
    # Standard run r2 is still fresh → gchat still fires.
    mock_gchat.send_message.assert_called_once()


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_non_prod_does_not_send(mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat):
    mock_cfg_cls.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory(environment="forno")

    now = datetime.now(timezone.utc)
    running, history = _running_and_history_results(now)
    session = mock.MagicMock()
    session.execute.side_effect = [running, history]

    monitor_dag_runtimes(session=session)

    mock_jira_cls.return_value.create_alert.assert_not_called()
    mock_gchat.send_message.assert_not_called()
    mock_var.set.assert_not_called()


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_failed_jira_delivery_is_not_recorded(
    mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat
):
    mock_cfg_cls.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()
    # JiraOps returns a non-2xx response → raise_for_status raises.
    failing_response = mock.MagicMock()
    failing_response.raise_for_status.side_effect = Exception("502 Bad Gateway")
    mock_jira_cls.return_value.create_alert.return_value = failing_response
    mock_gchat.send_message.return_value = True

    now = datetime.now(timezone.utc)
    running, history = _running_and_history_results(now)
    session = mock.MagicMock()
    session.execute.side_effect = [running, history]

    monitor_dag_runtimes(session=session)

    saved = json.loads(mock_var.set.call_args.args[1])
    # Critical run failed delivery → NOT recorded, so it retries next cycle.
    assert f"{_CRITICAL_DAG}|r1" not in saved
    # Standard run delivered fine → recorded.
    assert f"{_STANDARD_DAG}|r2" in saved


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_jira_network_error_does_not_block_gchat(
    mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat
):
    # A raised error (bad creds / network) from create_alert must not abort the task;
    # the independent standard-tier gchat send still runs and is recorded.
    mock_cfg_cls.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()
    mock_jira_cls.return_value.create_alert.side_effect = ConnectionError("boom")
    mock_gchat.send_message.return_value = True

    now = datetime.now(timezone.utc)
    running, history = _running_and_history_results(now)
    session = mock.MagicMock()
    session.execute.side_effect = [running, history]

    monitor_dag_runtimes(session=session)

    mock_gchat.send_message.assert_called_once()
    saved = json.loads(mock_var.set.call_args.args[1])
    assert f"{_CRITICAL_DAG}|r1" not in saved  # jira failed → retried next cycle
    assert f"{_STANDARD_DAG}|r2" in saved  # gchat delivered → recorded


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_missing_gchat_webhook_is_not_recorded(
    mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat
):
    mock_cfg_cls.return_value.get_config.side_effect = _config_get

    def var_get(key, default_var=None):
        if key == _WEBHOOK_KEY:  # webhook not provisioned yet
            return default_var
        if key == "environment":
            return "prod"
        if key == DEDUP_VARIABLE_KEY:
            return "{}"
        if key == JIRA_OPS_VARIABLE:
            return json.dumps({"username": "u", "token": "t", "cloud_id": "c"})
        return default_var

    mock_var.get.side_effect = var_get
    mock_jira_cls.return_value.create_alert.return_value = mock.MagicMock()

    now = datetime.now(timezone.utc)
    running, history = _running_and_history_results(now)
    session = mock.MagicMock()
    session.execute.side_effect = [running, history]

    monitor_dag_runtimes(session=session)

    mock_gchat.send_message.assert_not_called()
    saved = json.loads(mock_var.set.call_args.args[1])
    # Critical still delivered via JiraOps → recorded.
    assert f"{_CRITICAL_DAG}|r1" in saved
    # Standard skipped (no webhook) → NOT recorded, retries next cycle.
    assert f"{_STANDARD_DAG}|r2" not in saved


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_failed_gchat_send_is_not_recorded(
    mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat
):
    mock_cfg_cls.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()
    mock_jira_cls.return_value.create_alert.return_value = mock.MagicMock()
    mock_gchat.send_message.return_value = False  # delivery failed

    now = datetime.now(timezone.utc)
    running, history = _running_and_history_results(now)
    session = mock.MagicMock()
    session.execute.side_effect = [running, history]

    monitor_dag_runtimes(session=session)

    saved = json.loads(mock_var.set.call_args.args[1])
    assert f"{_CRITICAL_DAG}|r1" in saved
    assert f"{_STANDARD_DAG}|r2" not in saved


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_no_running_runs_short_circuits(
    mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat
):
    mock_cfg_cls.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()
    empty = mock.MagicMock()
    empty.fetchall.return_value = []
    session = mock.MagicMock()
    session.execute.return_value = empty

    monitor_dag_runtimes(session=session)

    mock_jira_cls.return_value.create_alert.assert_not_called()
    mock_gchat.send_message.assert_not_called()


# --------------------------------------------------------------------------- #
# Test/simulation mode (conf-driven)
# --------------------------------------------------------------------------- #
class TestParseTestOptions:
    def test_empty_conf_is_normal_run(self):
        opts = _parse_test_options(None)
        assert opts == {
            "simulate": False,
            "simulate_dags": None,
            "dry_run": False,
            "force_send": False,
            "test_webhook": None,
            "test_responder_team_id": None,
            "only_dags": None,
        }

    def test_simulate_defaults_dry_run_true(self):
        assert _parse_test_options({"simulate": True})["dry_run"] is True

    def test_force_send_defaults_dry_run_false(self):
        # Forcing a send clearly intends delivery, so dry_run defaults off.
        assert (
            _parse_test_options({"simulate": True, "force_send": True})["dry_run"]
            is False
        )

    def test_explicit_dry_run_wins_over_force_send(self):
        assert (
            _parse_test_options(
                {"simulate": True, "force_send": True, "dry_run": True}
            )["dry_run"]
            is True
        )

    def test_explicit_overrides(self):
        opts = _parse_test_options(
            {
                "simulate": True,
                "dry_run": False,
                "force_send": True,
                "test_webhook": "https://x",
                "test_responder_team_id": "team-1",
                "only_dags": ["a"],
            }
        )
        assert opts["dry_run"] is False
        assert opts["force_send"] is True
        assert opts["test_webhook"] == "https://x"
        assert opts["test_responder_team_id"] == "team-1"
        assert opts["only_dags"] == ["a"]


def test_synthetic_findings_default_covers_both_tiers():
    findings = _synthetic_findings(_CONFIG)
    tiers = {f["tier"] for f in findings}
    assert tiers == {"critical", "standard"}
    # The first configured critical id is used for the critical synthetic finding.
    assert any(f["dag_id"] == _CRITICAL_DAG for f in findings)


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_simulate_dry_run_sends_nothing(
    mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat
):
    mock_cfg_cls.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()

    # simulate defaults dry_run=True → no DB access, no delivery, no state writes.
    monitor_dag_runtimes(session=mock.MagicMock(), run_conf={"simulate": True})

    mock_jira_cls.return_value.create_alert.assert_not_called()
    mock_gchat.send_message.assert_not_called()
    mock_var.set.assert_not_called()


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_simulate_force_send_routes_to_test_destinations(
    mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat
):
    mock_cfg_cls.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory(environment="forno")
    mock_jira_cls.return_value.create_alert.return_value = mock.MagicMock()
    mock_gchat.send_message.return_value = True

    # No explicit dry_run → force_send implies delivery (the Forno validation recipe).
    monitor_dag_runtimes(
        session=mock.MagicMock(),
        run_conf={
            "simulate": True,
            "force_send": True,
            "test_webhook": "https://chat.example.com/TEST",
            "test_responder_team_id": "test-team-123",
        },
    )

    # Critical synthetic finding routed to the TEST team, tagged, and marked [TEST].
    mock_jira_cls.return_value.create_alert.assert_called_once()
    _, jira_kwargs = mock_jira_cls.return_value.create_alert.call_args
    assert jira_kwargs["responder_team_id"] == "test-team-123"
    assert "test" in jira_kwargs["tags"]
    assert jira_kwargs["message"].startswith("[TEST]")

    # Standard synthetic finding posted to the throwaway webhook.
    sent_message = mock_gchat.send_message.call_args.args[0]
    assert sent_message.destination == "https://chat.example.com/TEST"

    # Simulated runs never touch the dedup state.
    mock_var.set.assert_not_called()


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_force_send_critical_without_test_team_is_not_paged(
    mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat
):
    mock_cfg_cls.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory(environment="forno")
    mock_gchat.send_message.return_value = True

    # force_send delivery, but no test team provided → critical must be downgraded to
    # log-only so a test trigger never reaches the real Data Engineering on-call.
    monitor_dag_runtimes(
        session=mock.MagicMock(),
        run_conf={
            "simulate": True,
            "dry_run": False,
            "force_send": True,
            "test_webhook": "https://chat.example.com/TEST",
        },
    )

    mock_jira_cls.return_value.create_alert.assert_not_called()
    # Standard tier still delivers to the test webhook.
    mock_gchat.send_message.assert_called_once()


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_only_dags_filters_evaluated_runs(
    mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat
):
    mock_cfg_cls.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()
    mock_jira_cls.return_value.create_alert.return_value = mock.MagicMock()
    mock_gchat.send_message.return_value = True

    now = datetime.now(timezone.utc)
    running, history = _running_and_history_results(now)
    session = mock.MagicMock()
    session.execute.side_effect = [running, history]

    # Restrict to the standard DAG only → no JiraOps page, gchat fires for it.
    monitor_dag_runtimes(session=session, run_conf={"only_dags": [_STANDARD_DAG]})

    mock_jira_cls.return_value.create_alert.assert_not_called()
    mock_gchat.send_message.assert_called_once()


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_reads_trigger_conf_from_dag_run_not_context_conf(
    mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat
):
    # Airflow injects context["conf"] = the global AirflowConfigParser (NOT a dict) and
    # puts the trigger payload on dag_run.conf. The callable must read dag_run.conf and
    # must not choke on the context "conf" kwarg. Regression for the param-name collision.
    mock_cfg_cls.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()

    class _FakeAirflowConf:
        def get(self, *args, **kwargs):  # AirflowConfigParser.get(section, key, ...)
            raise AssertionError("must not read options off the Airflow config object")

    dag_run = SimpleNamespace(conf={"simulate": True, "dry_run": True})

    # Mimic PythonOperator: session via provide_session, plus context kwargs incl. `conf`.
    monitor_dag_runtimes(
        session=mock.MagicMock(),
        conf=_FakeAirflowConf(),
        dag_run=dag_run,
    )

    # dag_run.conf → simulate dry-run → nothing delivered, no crash.
    mock_jira_cls.return_value.create_alert.assert_not_called()
    mock_gchat.send_message.assert_not_called()
    mock_var.set.assert_not_called()


# --------------------------------------------------------------------------- #
# Hardening: conf coercion, dedup-state typing, prune scope, test-override gating
# --------------------------------------------------------------------------- #
class TestAsStrList:
    @pytest.mark.parametrize(
        "value,expected",
        [
            (None, None),
            (
                "bietlejuice.x",
                ["bietlejuice.x"],
            ),  # bare string → one element, not chars
            (["a", "b"], ["a", "b"]),
            ((1, 2), ["1", "2"]),
            (5, None),  # non-iterable → ignored
            ({"a": 1}, None),  # dict → ignored
        ],
    )
    def test_coerce(self, value, expected):
        assert _as_str_list(value) == expected

    def test_parse_options_coerces_dag_lists(self):
        opts = _parse_test_options(
            {"only_dags": "bietlejuice.x", "simulate_dags": "bietlejuice.y"}
        )
        assert opts["only_dags"] == ["bietlejuice.x"]
        assert opts["simulate_dags"] == ["bietlejuice.y"]


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
            mock_var.get.return_value = '{"a|1": "t"}'
            assert _load_dedup_state() == {"a|1": "t"}


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_only_dags_prune_keeps_other_running_dags_dedup(
    mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat
):
    # only_dags narrows evaluation to one DAG, but dedup pruning must use the FULL active
    # set so a still-running DAG outside only_dags keeps its dedup entry.
    mock_cfg_cls.return_value.get_config.side_effect = _config_get
    other_key = "bietlejuice.other_running|r9"
    mock_var.get.side_effect = _variable_get_factory(
        dedup_state=json.dumps({other_key: "2026-07-16T11:00:00+00:00"})
    )
    mock_gchat.send_message.return_value = True

    now = datetime.now(timezone.utc)
    running = mock.MagicMock()
    running.fetchall.return_value = [
        SimpleNamespace(
            dag_id=_STANDARD_DAG, run_id="r2", start_date=now - timedelta(minutes=60)
        ),
        SimpleNamespace(
            dag_id="bietlejuice.other_running",
            run_id="r9",
            start_date=now - timedelta(minutes=60),
        ),
    ]
    history = mock.MagicMock()
    history.fetchall.return_value = [
        SimpleNamespace(dag_id=_STANDARD_DAG, duration_s=600.0) for _ in range(10)
    ]
    session = mock.MagicMock()
    session.execute.side_effect = [running, history]

    monitor_dag_runtimes(session=session, run_conf={"only_dags": [_STANDARD_DAG]})

    saved = json.loads(mock_var.set.call_args.args[1])
    # other_running/r9 is still active (in the full set) → its dedup entry survives.
    assert other_key in saved
    # the evaluated standard run was delivered and recorded too.
    assert f"{_STANDARD_DAG}|r2" in saved


@mock.patch(f"{_MODULE}.GChatService")
@mock.patch(f"{_MODULE}.JiraOpsClient")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
def test_test_overrides_ignored_without_force_send(
    mock_cfg_cls, mock_var, mock_jira_cls, mock_gchat
):
    # A prod manual run passing test_webhook / test_responder_team_id but NOT force_send
    # must route real alerts to the configured webhook + default team, unmarked.
    mock_cfg_cls.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory(environment="prod")
    mock_jira_cls.return_value.create_alert.return_value = mock.MagicMock()
    mock_gchat.send_message.return_value = True

    now = datetime.now(timezone.utc)
    running, history = _running_and_history_results(now)
    session = mock.MagicMock()
    session.execute.side_effect = [running, history]

    monitor_dag_runtimes(
        session=session,
        run_conf={
            "test_webhook": "https://chat.example.com/THROWAWAY",
            "test_responder_team_id": "sneaky-team",
        },
    )

    # Critical → default team (responder_team_id None), NOT marked [TEST].
    _, jira_kwargs = mock_jira_cls.return_value.create_alert.call_args
    assert jira_kwargs["responder_team_id"] is None
    assert not jira_kwargs["message"].startswith("[TEST]")
    assert "test" not in jira_kwargs["tags"]
    # Standard → configured webhook, not the throwaway one.
    sent_message = mock_gchat.send_message.call_args.args[0]
    assert sent_message.destination == _WEBHOOK_URL
