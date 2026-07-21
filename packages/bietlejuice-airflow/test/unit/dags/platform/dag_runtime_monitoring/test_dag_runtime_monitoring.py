"""Unit tests for the platform dag_runtime_monitoring DAG logic and structure."""

import json
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest import mock

import pytest

from dags.platform.dag_runtime_monitoring.dag_runtime_monitoring import (
    _GCHAT_TEXT_MAX,
    _HISTORY_QUERY,
    _IMPACTED_DW_LIST_LIMIT,
    _JIRA_DESCRIPTION_MAX,
    _JIRA_MESSAGE_MAX,
    _RUNNING_QUERY,
    DAG_ID,
    DEDUP_VARIABLE_KEY,
    JIRA_OPS_VARIABLE,
    _as_str_list,
    _assign_alert_tiers,
    _build_alert_text,
    _effective_work_start,
    _enrich_findings_with_dw_impact,
    _entry_from_finding,
    _evaluate_all,
    _evaluate_runtime,
    _failed_text,
    _fetch_dag_owners,
    _fetch_run_states,
    _follow_up_clock_start,
    _format_duration,
    _format_impacted_dw_line,
    _impacts_critical,
    _initial_text,
    _live_impacted_dw_count,
    _load_dedup_state,
    _load_downstream_index_safe,
    _normalize_ledger,
    _parse_test_options,
    _percentile,
    _post_gchat,
    _resolve_config,
    _resolved_text,
    _synthetic_findings,
    _truncate_text,
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
        assert merged["percentile"] == 99
        assert merged["min_history_runs"] == 15
        assert merged["lookback_days"] == 30
        assert merged["min_alert_duration_minutes"] == 90
        assert merged["factor"] == 1.5

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
                work_start=None,
                has_execute_job_cluster=False,
            ),
            SimpleNamespace(
                dag_id=_STANDARD_DAG,
                run_id="r2",
                start_date=now - timedelta(minutes=60),
                work_start=None,
                has_execute_job_cluster=False,
            ),
            SimpleNamespace(
                dag_id="bietlejuice.fast_dag",
                run_id="r3",
                start_date=now - timedelta(seconds=30),
                work_start=None,
                has_execute_job_cluster=False,
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
                dag_id=_STANDARD_DAG,
                run_id="r2",
                start_date=now - timedelta(hours=5),
                work_start=None,
                has_execute_job_cluster=False,
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
                work_start=None,
                has_execute_job_cluster=False,
            ),
            SimpleNamespace(
                dag_id=_STANDARD_DAG,
                run_id="long",
                start_date=now - timedelta(minutes=90),
                work_start=None,
                has_execute_job_cluster=False,
            ),
        ]
        durations = {_CRITICAL_DAG: [600.0] * 10, _STANDARD_DAG: [600.0] * 10}
        by_dag = {
            f["dag_id"]: f for f in _evaluate_all(running, durations, now, config)
        }
        assert _CRITICAL_DAG not in by_dag
        assert _STANDARD_DAG in by_dag

    def test_skips_sensor_wait_before_execute_job_cluster(self):
        # Regression: dag_run started hours ago but execute-job-cluster not started yet.
        now = datetime(2026, 7, 16, 12, 0, tzinfo=timezone.utc)
        running = [
            SimpleNamespace(
                dag_id=_STANDARD_DAG,
                run_id="sensor_wait",
                start_date=now - timedelta(hours=5),
                work_start=None,
                has_execute_job_cluster=True,
            )
        ]
        durations = {_STANDARD_DAG: [600.0] * 10}
        assert _evaluate_all(running, durations, now, _CONFIG) == []

    def test_uses_execute_job_cluster_work_start_for_elapsed(self):
        now = datetime(2026, 7, 16, 12, 0, tzinfo=timezone.utc)
        work_start = now - timedelta(minutes=90)
        running = [
            SimpleNamespace(
                dag_id=_STANDARD_DAG,
                run_id="after_cluster",
                start_date=now - timedelta(hours=5),  # sensor wait inflated
                work_start=work_start,
                has_execute_job_cluster=True,
            )
        ]
        durations = {_STANDARD_DAG: [600.0] * 10}
        findings = _evaluate_all(running, durations, now, _CONFIG)
        assert len(findings) == 1
        assert findings[0]["elapsed_s"] == pytest.approx(90 * 60)
        assert findings[0]["work_start_date"] == work_start.isoformat()


class TestEffectiveWorkStart:
    def test_legacy_without_ejc_uses_dag_start(self):
        now = datetime(2026, 7, 16, 12, 0, tzinfo=timezone.utc)
        row = SimpleNamespace(
            start_date=now - timedelta(hours=1),
            work_start=None,
            has_execute_job_cluster=False,
        )
        assert _effective_work_start(row) == row.start_date

    def test_ejc_present_but_not_started_returns_none(self):
        now = datetime(2026, 7, 16, 12, 0, tzinfo=timezone.utc)
        row = SimpleNamespace(
            start_date=now - timedelta(hours=5),
            work_start=None,
            has_execute_job_cluster=True,
        )
        assert _effective_work_start(row) is None

    def test_ejc_started_prefers_work_start(self):
        now = datetime(2026, 7, 16, 12, 0, tzinfo=timezone.utc)
        work_start = now - timedelta(minutes=30)
        row = SimpleNamespace(
            start_date=now - timedelta(hours=5),
            work_start=work_start,
            has_execute_job_cluster=True,
        )
        assert _effective_work_start(row) == work_start

    def test_follow_up_clock_prefers_ledger_then_row(self):
        now = datetime(2026, 7, 16, 12, 0, tzinfo=timezone.utc)
        ledger_start = now - timedelta(minutes=40)
        row_work = now - timedelta(minutes=30)
        entry = {"work_start_date": ledger_start.isoformat()}
        row = SimpleNamespace(start_date=now - timedelta(hours=2), work_start=row_work)
        assert _follow_up_clock_start(entry, row) == ledger_start
        assert _follow_up_clock_start({}, row) == row_work
        assert (
            _follow_up_clock_start({}, SimpleNamespace(start_date=now, work_start=None))
            == now
        )


def test_build_alert_text_contains_key_facts():
    finding = {
        "dag_id": _CRITICAL_DAG,
        "run_id": "r1",
        "elapsed_s": 3600,
        "baseline_s": 600,
        "history_count": 10,
        "percentile": 90,
        "pct_over": 500,
        "owner": "Data Platform",
        "impacted_dw_dags": ["bietlejuice.dw_foo"],
    }
    text = _build_alert_text(finding)
    assert text.startswith("🐌")
    assert _CRITICAL_DAG in text
    assert "• Owner: Data Platform" in text
    assert "P90" in text
    assert "(+500%)" in text
    assert "• Run: r1" in text
    assert "• Impacted DW (1): bietlejuice.dw_foo" in text


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
    "owner": "Data Fintech",
    "impacted_dw_dags": ["bietlejuice.dw_alpha", "bietlejuice.dw_beta"],
    "impacted_dw_count": 2,
}


def test_message_builders():
    initial = _initial_text(_ENTRY, 3600)
    assert initial.startswith("🐌")
    assert "running slower than usual" in initial
    assert "• Owner: Data Fintech" in initial
    assert "P90 baseline" in initial
    assert "• Impacted DW (2): bietlejuice.dw_alpha, bietlejuice.dw_beta" in initial
    assert "Tracking until it finishes." in initial
    update = _update_text(_ENTRY, 5400)
    assert update.startswith("🐌")
    assert "still running" in update
    assert "• Still blocking 2 dw_* DAG(s)" in update
    resolved = _resolved_text(_ENTRY, 3600)
    assert "finished after" in resolved
    assert "• Owner: Data Fintech" in resolved
    assert "FAILED" in _failed_text(_ENTRY, 3600)
    assert _STANDARD_DAG in resolved


def test_message_builders_without_baseline():
    # Back-compat entry (old ledger) has no baseline_s → messages omit the % detail.
    entry = {"dag_id": _STANDARD_DAG, "run_id": "r2", "tier": "standard"}
    assert "baseline unavailable" in _initial_text(entry, 3600)
    assert "• Owner: unknown" in _initial_text(entry, 3600)
    assert "• Impacted DW: none" in _initial_text(entry, 3600)
    assert "unknown time" in _resolved_text(entry, None)
    assert "Still blocking" not in _update_text(entry, 5400)


class TestTruncateText:
    def test_under_limit_unchanged(self):
        assert _truncate_text("hello", 10) == "hello"

    def test_exact_limit_unchanged(self):
        assert _truncate_text("hello", 5) == "hello"

    def test_over_limit_adds_ellipsis(self):
        assert _truncate_text("hello world", 8) == "hello w…"
        assert len(_truncate_text("hello world", 8)) == 8

    def test_channel_limits_are_documented(self):
        assert _GCHAT_TEXT_MAX == 4096
        assert _JIRA_MESSAGE_MAX == 130
        assert _JIRA_DESCRIPTION_MAX == 15000


class TestFormatImpactedDwLine:
    def test_none_and_empty(self):
        assert _format_impacted_dw_line(None) == "• Impacted DW: none"
        assert _format_impacted_dw_line([]) == "• Impacted DW: none"

    def test_lists_all_when_under_limit(self):
        dags = ["bietlejuice.dw_a", "bietlejuice.dw_b"]
        assert (
            _format_impacted_dw_line(dags)
            == "• Impacted DW (2): bietlejuice.dw_a, bietlejuice.dw_b"
        )

    def test_truncates_after_limit(self):
        dags = [f"bietlejuice.dw_{i:02d}" for i in range(_IMPACTED_DW_LIST_LIMIT + 5)]
        text = _format_impacted_dw_line(dags)
        assert f"• Impacted DW ({len(dags)}):" in text
        assert "… and 5 more" in text
        assert f"bietlejuice.dw_{_IMPACTED_DW_LIST_LIMIT - 1:02d}" in text
        assert f"bietlejuice.dw_{_IMPACTED_DW_LIST_LIMIT:02d}" not in text


class TestFetchDagOwners:
    def test_parses_primary_owner(self):
        session = mock.MagicMock()
        session.execute.return_value.fetchall.return_value = [
            SimpleNamespace(dag_id="a", owners="Data Platform, other"),
            SimpleNamespace(dag_id="b", owners=""),
            SimpleNamespace(dag_id="c", owners=None),
        ]
        with mock.patch(
            f"{_MODULE}._owner_from_serialized_dag", return_value=None
        ) as mock_ser:
            assert _fetch_dag_owners(session, ["a", "b", "c"]) == {
                "a": "Data Platform",
                "b": "unknown",
                "c": "unknown",
            }
        mock_ser.assert_any_call(session, "b")
        mock_ser.assert_any_call(session, "c")

    def test_falls_back_to_serialized_dag_when_owners_blank(self):
        session = mock.MagicMock()
        session.execute.return_value.fetchall.return_value = [
            SimpleNamespace(dag_id="bietlejuice.dw_customer_support", owners=None),
        ]
        with mock.patch(
            f"{_MODULE}._owner_from_serialized_dag",
            return_value="Data SS",
        ) as mock_ser:
            assert _fetch_dag_owners(session, ["bietlejuice.dw_customer_support"]) == {
                "bietlejuice.dw_customer_support": "Data SS"
            }
        mock_ser.assert_called_once_with(session, "bietlejuice.dw_customer_support")

    def test_empty_dag_ids(self):
        session = mock.MagicMock()
        assert _fetch_dag_owners(session, []) == {}
        session.execute.assert_not_called()


class TestOwnerFromSerializedDag:
    def test_reads_serialized_owner(self):
        with mock.patch("airflow.models.serialized_dag.SerializedDagModel") as mock_sdm:
            mock_sdm.get.return_value = SimpleNamespace(
                dag=SimpleNamespace(owner="Data SS, other")
            )
            from dags.platform.dag_runtime_monitoring.dag_runtime_monitoring import (
                _owner_from_serialized_dag,
            )

            session = mock.MagicMock()
            assert _owner_from_serialized_dag(session, "d1") == "Data SS"
            mock_sdm.get.assert_called_once_with("d1", session=session)

    def test_returns_none_when_missing(self):
        with mock.patch("airflow.models.serialized_dag.SerializedDagModel") as mock_sdm:
            mock_sdm.get.return_value = None
            from dags.platform.dag_runtime_monitoring.dag_runtime_monitoring import (
                _owner_from_serialized_dag,
            )

            assert _owner_from_serialized_dag(mock.MagicMock(), "missing") is None


_SAMPLE_IMPACT_DEPS = {
    # STANDARD does not block CRITICAL → stays Chat-only when critical_dags is set.
    "bietlejuice.dw_impacted": [
        f"{_STANDARD_DAG}:load-enrich-table:first-run-of-day",
    ],
    "bietlejuice.metric_not_listed": [
        f"{_STANDARD_DAG}:load-enrich-table:first-run-of-day",
    ],
}


class TestEnrichFindingsWithDwImpact:
    def test_attaches_transitive_dw_only(self):
        from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
            BietlejuiceDependencyHelper,
        )

        findings = [{"dag_id": _STANDARD_DAG}]
        index = BietlejuiceDependencyHelper.build_downstream_index(_SAMPLE_IMPACT_DEPS)
        _enrich_findings_with_dw_impact(findings, index)
        assert findings[0]["impacted_dw_dags"] == ["bietlejuice.dw_impacted"]
        assert findings[0]["impacted_dw_count"] == 1

    def test_empty_index_yields_empty_list(self):
        findings = [{"dag_id": _STANDARD_DAG}]
        _enrich_findings_with_dw_impact(findings, {})
        assert findings[0]["impacted_dw_dags"] == []
        assert findings[0]["impacted_dw_count"] == 0


@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    side_effect=RuntimeError("boom"),
)
def test_load_downstream_index_safe_returns_none_on_read_error(mock_read):
    assert _load_downstream_index_safe() is None
    mock_read.assert_called_once()


@pytest.mark.parametrize(
    "invalid_upstreams",
    [
        {},
        {"foo": []},
        {"any": "not-a-list"},
    ],
)
@mock.patch(f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies")
def test_load_downstream_index_safe_returns_none_on_invalid_upstream_shape(
    mock_read, invalid_upstreams
):
    # Invalid shapes raise ValueError in find_unique_dependencies_in_dependency_object;
    # the monitor must not abort — alerts continue with • Impacted DW: none.
    mock_read.return_value = {"bietlejuice.dependent": invalid_upstreams}
    assert _load_downstream_index_safe() is None
    mock_read.assert_called_once()


@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    return_value=_SAMPLE_IMPACT_DEPS,
)
def test_load_downstream_index_safe_builds_index(mock_read):
    index = _load_downstream_index_safe()
    assert index[_STANDARD_DAG] == {
        "bietlejuice.dw_impacted",
        "bietlejuice.metric_not_listed",
    }
    mock_read.assert_called_once()


class TestAssignAlertTiers:
    """Tier = Chat+Jira when critical or blocking; else Chat-only. Never drop."""

    _ORPHAN = "bietlejuice.orphan_no_critical_path"
    _INDEX = {
        _STANDARD_DAG: {_CRITICAL_DAG, "bietlejuice.dw_other"},
        _ORPHAN: {"bietlejuice.unrelated_leaf"},
    }

    def _finding(self, dag_id, tier="standard"):
        return {
            "dag_id": dag_id,
            "run_id": "r1",
            "tier": tier,
            "elapsed_s": 3600.0,
            "baseline_s": 1500.0,
            "pct_over": 140,
        }

    def test_empty_critical_all_standard(self):
        findings = [
            self._finding(self._ORPHAN),
            self._finding(_CRITICAL_DAG, tier="critical"),
        ]
        _assign_alert_tiers(findings, [], self._INDEX)
        assert all(f["tier"] == "standard" for f in findings)
        assert not _impacts_critical(_CRITICAL_DAG, set(), self._INDEX)

    def test_self_critical_pages_jira(self):
        findings = [self._finding(_CRITICAL_DAG)]
        _assign_alert_tiers(findings, [_CRITICAL_DAG], self._INDEX)
        assert findings[0]["tier"] == "critical"
        assert _impacts_critical(_CRITICAL_DAG, {_CRITICAL_DAG}, self._INDEX)

    def test_upstream_blocking_critical_pages_jira(self):
        findings = [self._finding(_STANDARD_DAG)]
        _assign_alert_tiers(findings, [_CRITICAL_DAG], self._INDEX)
        assert findings[0]["tier"] == "critical"
        assert _impacts_critical(_STANDARD_DAG, {_CRITICAL_DAG}, self._INDEX)

    def test_no_path_to_critical_chat_only(self):
        findings = [self._finding(self._ORPHAN)]
        _assign_alert_tiers(findings, [_CRITICAL_DAG], self._INDEX)
        assert findings[0]["tier"] == "standard"
        assert not _impacts_critical(self._ORPHAN, {_CRITICAL_DAG}, self._INDEX)


@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    return_value={},
)
def test_load_downstream_index_safe_returns_empty_dict_when_file_empty(mock_read):
    assert _load_downstream_index_safe() == {}
    mock_read.assert_called_once()


class TestLiveImpactedDwCount:
    def test_unavailable_index_returns_none(self):
        assert _live_impacted_dw_count(_STANDARD_DAG, None) is None

    def test_empty_index_returns_zero(self):
        assert _live_impacted_dw_count(_STANDARD_DAG, {}) == 0

    def test_recomputes_from_index(self):
        from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
            BietlejuiceDependencyHelper,
        )

        index = BietlejuiceDependencyHelper.build_downstream_index(_SAMPLE_IMPACT_DEPS)
        assert _live_impacted_dw_count(_STANDARD_DAG, index) == 1


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
    assert "execute-job-cluster" in sql
    assert "task_instance" in sql


def test_running_query_constrains_task_instance_to_running_runs():
    """Regression: do not aggregate all execute-job-cluster* TIs before joining (#26399)."""
    sql = " ".join(str(_RUNNING_QUERY).split())
    assert "WITH running AS" in sql
    assert "FROM running AS r" in sql or "FROM running AS r".lower() in sql.lower()
    # Unbounded pre-aggregate pattern from the timed-out query must stay gone.
    assert "FROM task_instance WHERE task_id LIKE" not in sql.replace("\n", " ")


def test_history_query_joins_task_instance_from_filtered_dag_run():
    sql = " ".join(str(_HISTORY_QUERY).split())
    assert "FROM dag_run AS dr" in sql
    assert "LEFT JOIN task_instance AS ti" in sql
    assert "dr.dag_id IN" in sql
    assert "dr.end_date >=" in sql


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
    def test_truncates_text_to_gchat_limit(self, mock_requests):
        mock_requests.post.return_value = mock.MagicMock()
        oversized = "x" * (_GCHAT_TEXT_MAX + 50)
        assert _post_gchat(_WEBHOOK_URL, oversized, "k") is True
        text = mock_requests.post.call_args.kwargs["json"]["text"]
        assert len(text) == _GCHAT_TEXT_MAX
        assert text.endswith("…")

    @mock.patch(f"{_MODULE}.requests")
    def test_returns_false_on_error(self, mock_requests):
        mock_requests.post.return_value.raise_for_status.side_effect = Exception("500")
        assert _post_gchat(_WEBHOOK_URL, "hi", "k") is False

    def test_no_webhook_returns_false(self):
        assert _post_gchat(None, "hi", "k") is False


class TestSendJiraAlertTruncation:
    @mock.patch(f"{_MODULE}.JiraOpsClient")
    @mock.patch(f"{_MODULE}.Variable")
    def test_truncates_message_and_description(self, mock_var, mock_client_cls):
        mock_var.get.return_value = json.dumps(
            {"username": "u", "token": "t", "cloud_id": "c"}
        )
        client = mock_client_cls.return_value
        client.create_alert.return_value = mock.MagicMock()
        long_dag = "bietlejuice." + ("x" * 200)
        finding = {
            "dag_id": long_dag,
            "run_id": "r1",
            "elapsed_s": 3600,
            "baseline_s": 600,
            "percentile": 90,
            "pct_over": 500,
            "history_count": 3,
            "owner": "Data Platform",
            "impacted_dw_dags": [f"bietlejuice.dw_{i}" for i in range(40)],
        }
        from dags.platform.dag_runtime_monitoring.dag_runtime_monitoring import (
            _send_jira_alert,
        )

        assert _send_jira_alert(finding) is True
        kwargs = client.create_alert.call_args.kwargs
        assert len(kwargs["message"]) <= _JIRA_MESSAGE_MAX
        assert kwargs["message"].endswith("…")
        assert len(kwargs["description"]) <= _JIRA_DESCRIPTION_MAX
        assert kwargs["extra_properties"]["DAGOwner"] == "Data Platform"

    @mock.patch(f"{_MODULE}._build_alert_text", side_effect=KeyError("elapsed_s"))
    @mock.patch(f"{_MODULE}.JiraOpsClient")
    @mock.patch(f"{_MODULE}.Variable")
    def test_description_build_failure_returns_false(
        self, mock_var, mock_client_cls, _mock_build
    ):
        """Bad finding must not raise out of _send_jira_alert (task continues)."""
        from dags.platform.dag_runtime_monitoring.dag_runtime_monitoring import (
            _send_jira_alert,
        )

        finding = {"dag_id": "bietlejuice.broken", "run_id": "r1"}
        assert _send_jira_alert(finding) is False
        mock_client_cls.assert_not_called()
        mock_var.get.assert_not_called()


def _db_session():
    """Session mock whose execute().fetchall() is safe for ``_fetch_dag_owners``."""
    session = mock.MagicMock()
    session.execute.return_value.fetchall.return_value = []
    return session


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


def _running_row(dag_id, run_id, minutes_ago, now, *, work_start=None, has_ejc=False):
    return SimpleNamespace(
        dag_id=dag_id,
        run_id=run_id,
        start_date=now - timedelta(minutes=minutes_ago),
        work_start=work_start,
        has_execute_job_cluster=has_ejc,
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
@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    return_value=_SAMPLE_IMPACT_DEPS,
)
def test_new_standard_anomaly_posts_initial_and_tracks(
    mock_deps,
    mock_cfg,
    mock_var,
    mock_running,
    mock_durations,
    mock_states,
    mock_jira,
    mock_post,
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()
    now = datetime.now(timezone.utc)
    mock_running.return_value = [_running_row(_STANDARD_DAG, "r2", 90, now)]
    mock_durations.return_value = {_STANDARD_DAG: [600.0] * 10}

    monitor_dag_runtimes(session=_db_session())

    mock_jira.assert_not_called()
    mock_post.assert_called_once()
    text_arg = mock_post.call_args.args[1]
    assert "running slower than usual" in text_arg
    assert "bietlejuice.dw_impacted" in text_arg
    assert "bietlejuice.metric_not_listed" not in text_arg
    saved = _saved_ledger(mock_var)
    assert saved[f"{_STANDARD_DAG}|r2"]["tier"] == "standard"
    assert saved[f"{_STANDARD_DAG}|r2"]["baseline_s"] == 600.0
    assert saved[f"{_STANDARD_DAG}|r2"]["impacted_dw_dags"] == [
        "bietlejuice.dw_impacted"
    ]
    assert saved[f"{_STANDARD_DAG}|r2"]["impacted_dw_count"] == 1


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}._fetch_run_states", return_value={})
@mock.patch(f"{_MODULE}._fetch_recent_durations")
@mock.patch(f"{_MODULE}._fetch_running_runs")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    return_value=_SAMPLE_IMPACT_DEPS,
)
def test_new_critical_anomaly_pages_jira_with_dw_impact(
    mock_deps,
    mock_cfg,
    mock_var,
    mock_running,
    mock_durations,
    mock_states,
    mock_jira,
    mock_post,
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()
    now = datetime.now(timezone.utc)
    # Critical DAG is upstream of a DW DAG in this fixture graph via STANDARD? Use
    # a custom deps map where the critical DAG fans into dw_*.
    mock_deps.return_value = {
        "bietlejuice.dw_from_critical": [
            f"{_CRITICAL_DAG}:load-clean-table:first-run-of-day",
        ]
    }
    mock_running.return_value = [_running_row(_CRITICAL_DAG, "r1", 90, now)]
    mock_durations.return_value = {_CRITICAL_DAG: [600.0] * 10}

    monitor_dag_runtimes(session=_db_session())

    mock_jira.assert_called_once()
    mock_post.assert_called_once()  # critical → Chat + JiraOps
    finding_arg = mock_jira.call_args.args[0]
    assert finding_arg["impacted_dw_dags"] == ["bietlejuice.dw_from_critical"]
    saved = _saved_ledger(mock_var)
    assert saved[f"{_CRITICAL_DAG}|r1"]["tier"] == "critical"
    assert saved[f"{_CRITICAL_DAG}|r1"]["impacted_dw_count"] == 1


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=False)
@mock.patch(f"{_MODULE}._fetch_run_states", return_value={})
@mock.patch(f"{_MODULE}._fetch_recent_durations")
@mock.patch(f"{_MODULE}._fetch_running_runs")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    return_value=_SAMPLE_IMPACT_DEPS,
)
def test_critical_jira_failure_does_not_track_despite_chat_ok(
    mock_deps,
    mock_cfg,
    mock_var,
    mock_running,
    mock_durations,
    mock_states,
    mock_jira,
    mock_post,
):
    """Regression: Chat success must not ledger a critical run when JiraOps fails.

    Otherwise the next cycle skips the finding (already tracked) and on-call is
    never paged despite _send_jira_alert logging a next-cycle retry.
    """
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()
    now = datetime.now(timezone.utc)
    mock_running.return_value = [_running_row(_CRITICAL_DAG, "r1", 90, now)]
    mock_durations.return_value = {_CRITICAL_DAG: [600.0] * 10}

    monitor_dag_runtimes(session=_db_session())

    mock_jira.assert_called_once()
    mock_post.assert_called_once()  # Chat still attempted for visibility
    assert f"{_CRITICAL_DAG}|r1" not in _saved_ledger(mock_var)


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}._fetch_run_states", return_value={})
@mock.patch(f"{_MODULE}._fetch_recent_durations")
@mock.patch(f"{_MODULE}._fetch_running_runs")
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
@mock.patch(f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies")
def test_upstream_blocking_critical_pages_jira_and_chat(
    mock_deps,
    mock_cfg,
    mock_var,
    mock_running,
    mock_durations,
    mock_states,
    mock_jira,
    mock_post,
):
    """Slow upstream of a critical DAG → Chat + JiraOps (same as membership)."""
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()
    now = datetime.now(timezone.utc)
    mock_deps.return_value = {
        _CRITICAL_DAG: [f"{_STANDARD_DAG}:load-enrich-table:first-run-of-day"],
    }
    mock_running.return_value = [_running_row(_STANDARD_DAG, "r2", 90, now)]
    mock_durations.return_value = {_STANDARD_DAG: [600.0] * 10}

    monitor_dag_runtimes(session=_db_session())

    mock_jira.assert_called_once()
    mock_post.assert_called_once()
    assert _saved_ledger(mock_var)[f"{_STANDARD_DAG}|r2"]["tier"] == "critical"


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    return_value=_SAMPLE_IMPACT_DEPS,
)
def test_simulate_attaches_dw_impact(
    mock_deps, mock_cfg, mock_var, mock_jira, mock_post
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()

    monitor_dag_runtimes(
        session=_db_session(),
        run_conf={
            "simulate": True,
            "force_send": True,
            "test_webhook": _WEBHOOK_URL,
            "simulate_dags": [_STANDARD_DAG],
        },
    )

    mock_post.assert_called_once()
    assert "bietlejuice.dw_impacted" in mock_post.call_args.args[1]


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
@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    return_value=_SAMPLE_IMPACT_DEPS,
)
def test_tracked_running_gets_update(
    mock_deps, mock_post, mock_states, mock_running, mock_var, mock_cfg
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

    monitor_dag_runtimes(session=_db_session())

    mock_post.assert_called_once()
    text = mock_post.call_args.args[1]
    assert "still running" in text
    assert "• Still blocking 1 dw_* DAG(s)" in text  # live count from deps
    assert f"{_STANDARD_DAG}|r2" in _saved_ledger(mock_var)  # kept


@_lifecycle_patches
@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    return_value=_SAMPLE_IMPACT_DEPS,
)
def test_follow_up_elapsed_uses_ledger_work_start_date(
    mock_deps, mock_post, mock_states, mock_running, mock_var, mock_cfg
):
    # Follow-up must report work elapsed (~40m), not full dag_run wall time (~2h).
    mock_cfg.return_value.get_config.side_effect = _config_get
    now = datetime.now(timezone.utc)
    work_start = now - timedelta(minutes=40)
    entry = {
        **_ENTRY,
        "work_start_date": work_start.isoformat(),
    }
    ledger = {f"{_STANDARD_DAG}|r2": entry}
    mock_var.get.side_effect = _variable_get_factory(ledger=json.dumps(ledger))
    mock_states.return_value = {
        (_STANDARD_DAG, "r2"): SimpleNamespace(
            dag_id=_STANDARD_DAG,
            run_id="r2",
            state="running",
            start_date=now - timedelta(hours=2),
            end_date=None,
            work_start=work_start,
        )
    }

    monitor_dag_runtimes(session=_db_session())

    mock_post.assert_called_once()
    text = mock_post.call_args.args[1]
    assert "still running" in text
    assert "40m" in text
    assert "2h" not in text


@_lifecycle_patches
@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    side_effect=RuntimeError("deps unavailable"),
)
def test_tracked_running_keeps_ledger_impact_when_deps_unavailable(
    mock_deps, mock_post, mock_states, mock_running, mock_var, mock_cfg
):
    # Regression: a later-cycle deps load failure must not wipe Still blocking N
    # by forcing live_count=0 over the ledger snapshot from the initial alert.
    mock_cfg.return_value.get_config.side_effect = _config_get
    ledger = {f"{_STANDARD_DAG}|r2": dict(_ENTRY)}  # impacted_dw_count=2
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

    monitor_dag_runtimes(session=_db_session())

    mock_post.assert_called_once()
    text = mock_post.call_args.args[1]
    assert "• Still blocking 2 dw_* DAG(s)" in text


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

    monitor_dag_runtimes(session=_db_session())

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

    monitor_dag_runtimes(session=_db_session())

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

    monitor_dag_runtimes(session=_db_session())

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

    monitor_dag_runtimes(session=_db_session())

    assert "finished after" in mock_post.call_args.args[1]
    assert f"{_STANDARD_DAG}|r2" in _saved_ledger(mock_var)  # retried next cycle


@_lifecycle_patches
def test_tracked_critical_terminal_posts_chat_close(
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

    monitor_dag_runtimes(session=_db_session())

    mock_post.assert_called_once()
    assert "finished after" in mock_post.call_args.args[1]
    assert f"{_CRITICAL_DAG}|r1" not in _saved_ledger(mock_var)


@_lifecycle_patches
def test_old_ledger_critical_string_gets_gchat_follow_up(
    mock_post, mock_states, mock_running, mock_var, mock_cfg
):
    # Old Variable format: bare timestamp. After normalize to critical tier, Chat
    # follow-ups still apply (critical is Chat + JiraOps, not Jira-only).
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

    monitor_dag_runtimes(session=_db_session())

    mock_post.assert_called_once()
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

    monitor_dag_runtimes(session=_db_session())

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

    monitor_dag_runtimes(session=_db_session())

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
@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    return_value=_SAMPLE_IMPACT_DEPS,
)
def test_only_dags_filters_evaluated_runs(
    mock_deps,
    mock_cfg,
    mock_var,
    mock_running,
    mock_durations,
    mock_states,
    mock_jira,
    mock_post,
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

    monitor_dag_runtimes(session=_db_session(), run_conf={"only_dags": [_STANDARD_DAG]})

    mock_jira.assert_not_called()  # critical filtered out
    mock_post.assert_called_once()


# --------------------------------------------------------------------------- #
# Simulate / test mode
# --------------------------------------------------------------------------- #
# Default synthetic standard finding must transitively impact critical_dags or
# the impact filter drops it when the YAML list is non-empty.
# Empty deps: default synthetic critical (membership) → Chat+Jira; synthetic
# standard (no path) → Chat only.
_SIMULATE_DEPS = {}


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    return_value=_SIMULATE_DEPS,
)
def test_simulate_dry_run_sends_nothing(
    mock_deps, mock_cfg, mock_var, mock_jira, mock_post
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()

    monitor_dag_runtimes(session=_db_session(), run_conf={"simulate": True})

    mock_jira.assert_not_called()
    mock_post.assert_not_called()
    mock_var.set.assert_not_called()


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    return_value=_SIMULATE_DEPS,
)
def test_simulate_force_send_posts_initial_to_test_destinations(
    mock_deps, mock_cfg, mock_var, mock_jira, mock_post
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory(environment="forno")

    monitor_dag_runtimes(
        session=_db_session(),
        run_conf={
            "simulate": True,
            "force_send": True,
            "test_webhook": "https://chat.example.com/TEST",
            "test_responder_team_id": "test-team-123",
        },
    )

    # Critical synthetic → JiraOps + Chat; standard synthetic → Chat only.
    _, jira_kwargs = mock_jira.call_args
    assert jira_kwargs["responder_team_id"] == "test-team-123"
    assert jira_kwargs["test"] is True
    assert mock_jira.call_count == 1
    assert mock_post.call_count == 2
    assert all(
        call.args[0] == "https://chat.example.com/TEST"
        for call in mock_post.call_args_list
    )
    mock_var.set.assert_not_called()  # simulate never writes the ledger


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    return_value=_SIMULATE_DEPS,
)
def test_force_send_critical_without_test_team_is_not_paged(
    mock_deps, mock_cfg, mock_var, mock_jira, mock_post
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory(environment="forno")

    monitor_dag_runtimes(
        session=_db_session(),
        run_conf={
            "simulate": True,
            "force_send": True,
            "test_webhook": "https://chat.example.com/TEST",
        },
    )

    mock_jira.assert_not_called()  # critical refused without test team
    assert mock_post.call_count == 2  # both critical + standard still Chat
    mock_var.set.assert_not_called()


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
        session=_db_session(), conf=_FakeAirflowConf(), dag_run=dag_run
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
            "critical_dags": None,
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
            {
                "only_dags": "bietlejuice.x",
                "simulate_dags": "bietlejuice.y",
                "critical_dags": "bietlejuice.z",
            }
        )
        assert opts["only_dags"] == ["bietlejuice.x"]
        assert opts["simulate_dags"] == ["bietlejuice.y"]
        assert opts["critical_dags"] == ["bietlejuice.z"]


@mock.patch(f"{_MODULE}._post_gchat", return_value=True)
@mock.patch(f"{_MODULE}._send_jira_alert", return_value=True)
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    return_value={},
)
def test_conf_critical_dags_override_makes_dag_critical(
    mock_deps, mock_cfg, mock_var, mock_jira, mock_post
):
    """Trigger conf ``critical_dags`` replaces YAML for that run (JiraOps tier)."""
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory()
    override_dag = "bietlejuice.conf_override_critical"

    monitor_dag_runtimes(
        session=mock.MagicMock(),
        run_conf={
            "simulate": True,
            "force_send": True,
            "test_responder_team_id": "test-team",
            "critical_dags": [override_dag],
            "simulate_dags": [override_dag],
        },
    )

    mock_jira.assert_called_once()
    finding = mock_jira.call_args.args[0]
    assert finding["dag_id"] == override_dag
    assert finding["tier"] == "critical"
    mock_post.assert_called_once()  # Chat + JiraOps


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
        "owner": "Data Platform",
        "impacted_dw_dags": ["bietlejuice.dw_impacted"],
        "impacted_dw_count": 1,
    }
    entry = _entry_from_finding(finding, first_alert_ts="ts")
    assert entry["baseline_s"] == 600.0
    assert entry["tier"] == "standard"
    assert entry["first_alert_ts"] == "ts"
    assert entry["owner"] == "Data Platform"
    assert entry["impacted_dw_dags"] == ["bietlejuice.dw_impacted"]
    assert entry["impacted_dw_count"] == 1


def test_update_text_uses_live_impacted_count_override():
    entry = dict(_ENTRY)
    entry["impacted_dw_count"] = 2
    text = _update_text(entry, 5400, impacted_dw_count=9)
    assert "• Still blocking 9 dw_* DAG(s)" in text


def test_update_text_falls_back_to_ledger_when_live_count_unavailable():
    entry = dict(_ENTRY)
    entry["impacted_dw_count"] = 2
    text = _update_text(entry, 5400, impacted_dw_count=None)
    assert "• Still blocking 2 dw_* DAG(s)" in text
