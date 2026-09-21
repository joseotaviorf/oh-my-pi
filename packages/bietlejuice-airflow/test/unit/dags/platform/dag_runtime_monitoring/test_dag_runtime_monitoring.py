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
    _KIND_DEADLINE_MISS,
    _KIND_MISSING_RUN,
    _KIND_SLOW,
    _MISSING_DATASET_LIST_LIMIT,
    _RUNNING_QUERY,
    _SLA_CANDIDATES_QUERY,
    _SLA_HISTORY_QUERY,
    _VERDICT_DROPPED_EVENT,
    _VERDICT_WAITING_UPSTREAM,
    DAG_ID,
    DEDUP_VARIABLE_KEY,
    JIRA_OPS_VARIABLE,
    _also_waiting_count,
    _apply_missing_run_cap,
    _apply_sla_follow_up,
    _as_str_list,
    _assign_alert_tiers,
    _build_alert_text,
    _build_dataset_indexes,
    _build_dataset_status,
    _build_upstream_index,
    _classify_dataset_state,
    _collect_sla_findings,
    _cycle_anchor,
    _dataset_blocked,
    _deadline_at,
    _deadline_run_id,
    _drop_alert_excluded_entries,
    _effective_work_start,
    _enrich_findings_with_dataset_state,
    _enrich_findings_with_dw_impact,
    _entry_from_finding,
    _evaluate_all,
    _evaluate_deadline_misses,
    _evaluate_runtime,
    _evaluate_sla_missing_runs,
    _expected_offset_minutes,
    _failed_text,
    _fetch_dag_owners,
    _fetch_dataset_satisfaction,
    _fetch_declared_criticality,
    _fetch_run_states,
    _fetch_sla_emitted,
    _follow_up_clock_start,
    _follow_up_tracked_runs,
    _format_duration,
    _format_impacted_dw_line,
    _impacts_critical,
    _initial_text,
    _is_alert_excluded_dag,
    _is_sla_candidate,
    _live_impacted_dw_count,
    _load_dedup_state,
    _load_downstream_index_safe,
    _load_upstream_index_safe,
    _missing_run_initial_text,
    _missing_run_started_text,
    _missing_run_update_text,
    _normalize_ledger,
    _offset_minutes,
    _parse_test_options,
    _percentile,
    _post_gchat,
    _producer_from_uri,
    _required_datasets,
    _resolve_anchor_hhmm,
    _resolve_config,
    _resolved_text,
    _select_sla_roots,
    _sla_run_id,
    _synthetic_findings,
    _synthetic_missing_run_findings,
    _truncate_text,
    _union_indexes,
    _update_text,
    dag,
    monitor_dag_runtimes,
)

_MODULE = "dags.platform.dag_runtime_monitoring.dag_runtime_monitoring"

# Fixed instant for end-to-end monitor calls: past the 10:00 São Paulo (13:00 UTC)
# deadline used by TestMonitorPagesDeadlineMiss.
_FROZEN_NOW = datetime(2026, 9, 17, 14, 0, tzinfo=timezone.utc)

_WEBHOOK_KEY = "GCHAT_DAG_RUNTIME_MONITORING_WEBHOOK"
_WEBHOOK_URL = "https://chat.example.com/hook?key=k&token=t"
_CRITICAL_DAG = "bietlejuice.ebdb_location"
_STANDARD_DAG = "bietlejuice.some_small_dag"
_QUINTOML_DAG = "quintoml.wonka.segmentation"

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
        assert merged["sla_enabled"] is True
        assert merged["sla_lookback_days"] == 14
        assert merged["sla_min_history_cycles"] == 10
        assert merged["sla_percentile"] == 90
        assert merged["sla_grace_minutes"] == 60
        assert merged["sla_cycle_anchor_local_time"] == "20:55"
        assert merged["sla_exclude_dag_prefixes"] == ["migration_"]
        assert merged["sla_exclude_dag_suffixes"] == ["__validation"]

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

    def test_skips_alert_excluded_quintoml_dags(self):
        now = datetime(2026, 7, 16, 12, 0, tzinfo=timezone.utc)
        running = [
            SimpleNamespace(
                dag_id=_QUINTOML_DAG,
                run_id="r1",
                start_date=now - timedelta(hours=5),
                work_start=None,
                has_execute_job_cluster=False,
            )
        ]
        durations = {_QUINTOML_DAG: [600.0] * 10}
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
    assert "• Impacted DW (1): dw_foo" in text


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
    assert "• Impacted DW (2): dw_alpha, dw_beta" in initial
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
        assert _format_impacted_dw_line(dags) == "• Impacted DW (2): dw_a, dw_b"

    def test_truncates_after_limit(self):
        dags = [f"bietlejuice.dw_{i:02d}" for i in range(_IMPACTED_DW_LIST_LIMIT + 5)]
        text = _format_impacted_dw_line(dags)
        assert f"• Impacted DW ({len(dags)}):" in text
        assert "… and 5 more" in text
        assert f"dw_{_IMPACTED_DW_LIST_LIMIT - 1:02d}" in text
        assert f"dw_{_IMPACTED_DW_LIST_LIMIT:02d}" not in text
        assert "bietlejuice." not in text

    def test_preserves_non_bietlejuice_namespaces(self):
        assert (
            _format_impacted_dw_line(["quintoml.wonka.segmentation"])
            == "• Impacted DW (1): quintoml.wonka.segmentation"
        )


class TestFetchDeclaredCriticality:
    def test_parses_tags_and_skips_malformed(self):
        session = mock.MagicMock()
        session.execute.return_value.fetchall.return_value = [
            ("a", "criticality:Critical"),
            ("b", "criticality:Low"),
            ("c", "sla_deadline_localtime:10:00"),
            ("d", "criticality:Bogus"),
        ]
        criticality_by_dag, deadline_by_dag = _fetch_declared_criticality(session)
        assert criticality_by_dag == {"a": "Critical", "b": "Low"}
        assert deadline_by_dag == {"c": "10:00"}


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

    def _missing_run_finding(self, dag_id):
        cycle = datetime(2026, 8, 16, 23, 55, tzinfo=timezone.utc)
        return {
            "kind": _KIND_MISSING_RUN,
            "dag_id": dag_id,
            "run_id": _sla_run_id(cycle),
            "tier": "standard",
            "late_by_s": 3600.0,
            "due_at": "2026-08-17T04:55:00+00:00",
        }

    def test_missing_run_member_pages_jira(self):
        findings = [self._missing_run_finding(_CRITICAL_DAG)]
        _assign_alert_tiers(findings, [_CRITICAL_DAG], self._INDEX)
        assert findings[0]["tier"] == "critical"

    def test_missing_run_upstream_of_critical_stays_standard(self):
        # Regression: the slow tier's transitive expansion must not page missing-run
        # upstreams (chronic-late layer of ~28 DAGs).
        findings = [self._missing_run_finding(_STANDARD_DAG)]
        _assign_alert_tiers(findings, [_CRITICAL_DAG], self._INDEX)
        assert findings[0]["tier"] == "standard"

    def test_missing_run_empty_critical_stays_standard(self):
        findings = [self._missing_run_finding(_CRITICAL_DAG)]
        _assign_alert_tiers(findings, [], self._INDEX)
        assert findings[0]["tier"] == "standard"

    def _deadline_miss_finding(self, dag_id):
        return {
            "kind": _KIND_DEADLINE_MISS,
            "dag_id": dag_id,
            "run_id": "deadline::2026-09-16T23:55:00+00:00",
            "tier": "standard",
            "late_by_s": 3600.0,
            "due_at": "2026-09-17T10:00:00+00:00",
        }

    def test_deadline_miss_member_pages_jira(self):
        findings = [self._deadline_miss_finding(_CRITICAL_DAG)]
        _assign_alert_tiers(findings, [_CRITICAL_DAG], self._INDEX)
        assert findings[0]["tier"] == "critical"

    def test_deadline_miss_upstream_of_critical_stays_standard(self):
        findings = [self._deadline_miss_finding(_STANDARD_DAG)]
        _assign_alert_tiers(findings, [_CRITICAL_DAG], self._INDEX)
        assert findings[0]["tier"] == "standard"


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

    def test_old_string_entry_deadline_run_id_sets_deadline_miss_kind(self):
        key = f"{_CRITICAL_DAG}|deadline::2026-09-16T23:55:00+00:00"
        raw = {key: "2026-09-17T11:00:00+00:00"}
        entry = _normalize_ledger(raw)[key]
        assert entry["kind"] == _KIND_DEADLINE_MISS


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

    @mock.patch(f"{_MODULE}.JiraOpsClient")
    @mock.patch(f"{_MODULE}.Variable")
    def test_missing_run_payload_has_sla_fields(self, mock_var, mock_client_cls):
        mock_var.get.return_value = json.dumps(
            {"username": "u", "token": "t", "cloud_id": "c"}
        )
        client = mock_client_cls.return_value
        client.create_alert.return_value = mock.MagicMock()
        cycle = datetime(2026, 8, 16, 23, 55, tzinfo=timezone.utc)
        finding = {
            "kind": _KIND_MISSING_RUN,
            "dag_id": _CRITICAL_DAG,
            "run_id": _sla_run_id(cycle),
            "tier": "critical",
            "late_by_s": 3600.0,
            "due_at": "2026-08-17T04:55:00+00:00",
            "owner": "Data Platform",
        }
        from dags.platform.dag_runtime_monitoring.dag_runtime_monitoring import (
            _send_jira_alert,
        )

        assert _send_jira_alert(finding) is True
        kwargs = client.create_alert.call_args.kwargs
        assert kwargs["message"].startswith("DAG missed SLA start:")
        assert "sla missing run" in kwargs["tags"]
        extra = kwargs["extra_properties"]
        assert extra["DueAt"] == finding["due_at"]
        assert "LateBy" in extra
        assert "PctOverBaseline" not in extra

    @mock.patch(f"{_MODULE}.JiraOpsClient")
    @mock.patch(f"{_MODULE}.Variable")
    def test_priority_p1_when_criticality_critical(self, mock_var, mock_client_cls):
        mock_var.get.return_value = json.dumps(
            {"username": "u", "token": "t", "cloud_id": "c"}
        )
        client = mock_client_cls.return_value
        client.create_alert.return_value = mock.MagicMock()
        finding = {
            "dag_id": _CRITICAL_DAG,
            "run_id": "r1",
            "elapsed_s": 3600,
            "baseline_s": 600,
            "percentile": 90,
            "pct_over": 500,
            "history_count": 3,
            "owner": "Data Platform",
            "criticality": "Critical",
        }
        from dags.platform.dag_runtime_monitoring.dag_runtime_monitoring import (
            _send_jira_alert,
        )

        assert _send_jira_alert(finding) is True
        kwargs = client.create_alert.call_args.kwargs
        assert kwargs["priority"] == "P1"
        assert kwargs["extra_properties"]["Criticality"] == "Critical"

    @mock.patch(f"{_MODULE}.JiraOpsClient")
    @mock.patch(f"{_MODULE}.Variable")
    def test_priority_p2_when_criticality_absent(self, mock_var, mock_client_cls):
        mock_var.get.return_value = json.dumps(
            {"username": "u", "token": "t", "cloud_id": "c"}
        )
        client = mock_client_cls.return_value
        client.create_alert.return_value = mock.MagicMock()
        finding = {
            "dag_id": _STANDARD_DAG,
            "run_id": "r1",
            "elapsed_s": 3600,
            "baseline_s": 600,
            "percentile": 90,
            "pct_over": 500,
            "history_count": 3,
            "owner": "Data Platform",
        }
        from dags.platform.dag_runtime_monitoring.dag_runtime_monitoring import (
            _send_jira_alert,
        )

        assert _send_jira_alert(finding) is True
        kwargs = client.create_alert.call_args.kwargs
        assert kwargs["priority"] == "P2"
        assert "Criticality" not in kwargs["extra_properties"]


def _db_session():
    """Session mock. Tag query returns Critical for ``_CRITICAL_DAG`` so
    ``monitor_dag_runtimes`` rebuilds the paging set the way production does."""
    session = mock.MagicMock()

    def _execute(query, *args, **kwargs):
        result = mock.MagicMock()
        if "dag_tag" in str(query).lower():
            result.fetchall.return_value = [
                (_CRITICAL_DAG, "criticality:Critical"),
            ]
        else:
            result.fetchall.return_value = []
        return result

    session.execute.side_effect = _execute
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
    assert "dw_impacted" in text_arg
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
def test_quintoml_anomaly_is_not_posted(
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
    mock_running.return_value = [_running_row(_QUINTOML_DAG, "r1", 90, now)]
    mock_durations.return_value = {_QUINTOML_DAG: [600.0] * 10}

    monitor_dag_runtimes(session=_db_session())

    mock_jira.assert_not_called()
    mock_post.assert_not_called()
    saved = _saved_ledger(mock_var)
    assert not any(_QUINTOML_DAG in key for key in saved)


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
    assert "dw_impacted" in mock_post.call_args.args[1]


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
@mock.patch(f"{_MODULE}._fetch_dataset_edges", lambda *_args, **_kwargs: None)
@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    side_effect=RuntimeError("deps unavailable"),
)
def test_tracked_running_keeps_ledger_impact_when_deps_unavailable(
    mock_deps, mock_post, mock_states, mock_running, mock_var, mock_cfg
):
    # Regression: a later-cycle graph load failure must not wipe Still blocking N
    # by forcing live_count=0 over the ledger snapshot from the initial alert.
    # Both graph sources must be down — the live dataset edges alone are enough to
    # rebuild a downstream index when dependencies.yaml cannot be read.
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
@mock.patch(f"{_MODULE}.Variable")
@mock.patch(f"{_MODULE}.ConfigurationService")
@mock.patch(
    f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
    return_value=_SIMULATE_DEPS,
)
def test_force_send_missing_run_without_test_team_is_not_paged(
    mock_deps, mock_cfg, mock_var, mock_jira, mock_post
):
    mock_cfg.return_value.get_config.side_effect = _config_get
    mock_var.get.side_effect = _variable_get_factory(environment="forno")

    monitor_dag_runtimes(
        session=_db_session(),
        run_conf={
            "simulate": True,
            "simulate_missing_runs": True,
            "simulate_dags": [_CRITICAL_DAG],
            "force_send": True,
            "test_webhook": "https://chat.example.com/TEST",
        },
    )

    mock_jira.assert_not_called()
    mock_post.assert_called_once()
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
            "simulate_missing_runs": False,
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

    def test_simulate_missing_runs_flag(self):
        assert (
            _parse_test_options({"simulate": True, "simulate_missing_runs": True})[
                "simulate_missing_runs"
            ]
            is True
        )


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
    assert entry["kind"] == "slow"
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


# --------------------------------------------------------------------------- #
# SLA start / missing-run guard
# --------------------------------------------------------------------------- #
_SLA_CONFIG = {
    **_CONFIG,
    "sla_enabled": True,
    "sla_lookback_days": 14,
    "sla_min_history_cycles": 10,
    "sla_percentile": 90,
    "sla_grace_minutes": 60,
    "sla_cycle_anchor_local_time": "20:55",
    "sla_exclude_dag_prefixes": ["migration_"],
    "sla_exclude_dag_suffixes": ["__validation"],
}


class TestCycleAnchor:
    def test_before_anchor_uses_previous_day(self):
        # 03:45 UTC on Jul 25 = 00:45 BRT — still after 20:55 BRT Jul 24.
        moment = datetime(2026, 7, 25, 3, 45, tzinfo=timezone.utc)
        anchor = _cycle_anchor(moment, hhmm="20:55")
        assert anchor == datetime(2026, 7, 24, 23, 55, tzinfo=timezone.utc)

    def test_after_anchor_same_local_day(self):
        # 01:00 UTC Jul 25 = 22:00 BRT Jul 24 — after 20:55 BRT Jul 24.
        moment = datetime(2026, 7, 25, 1, 0, tzinfo=timezone.utc)
        anchor = _cycle_anchor(moment, hhmm="20:55")
        assert anchor == datetime(2026, 7, 24, 23, 55, tzinfo=timezone.utc)

    def test_exactly_at_anchor(self):
        moment = datetime(2026, 7, 24, 23, 55, tzinfo=timezone.utc)
        assert _cycle_anchor(moment, hhmm="20:55") == moment

    def test_offset_no_midnight_wrap(self):
        # Start at 03:45 UTC Jul 25 → ~230 minutes after 23:55 UTC Jul 24.
        start = datetime(2026, 7, 25, 3, 45, tzinfo=timezone.utc)
        offset = _offset_minutes(start, hhmm="20:55")
        assert offset == pytest.approx(230.0)


class TestDeadlineAt:
    _CYCLE_START = datetime(2026, 9, 16, 23, 55, tzinfo=timezone.utc)

    def test_deadline_before_cycle_start_resolves_to_next_day(self):
        due = _deadline_at(self._CYCLE_START, "10:00")
        assert due == datetime(2026, 9, 17, 13, 0, tzinfo=timezone.utc)

    def test_deadline_morning_sla_resolves_to_next_day_utc_offset(self):
        due = _deadline_at(self._CYCLE_START, "08:00")
        assert due == datetime(2026, 9, 17, 11, 0, tzinfo=timezone.utc)

    def test_deadline_after_cycle_start_same_day(self):
        due = _deadline_at(self._CYCLE_START, "23:59")
        assert due == datetime(2026, 9, 17, 2, 59, tzinfo=timezone.utc)


class TestExpectedOffsetMinutes:
    def test_insufficient_history_returns_none(self):
        assert (
            _expected_offset_minutes([10.0] * 5, percentile=90, min_history=10) is None
        )

    def test_percentile_with_iqr_trim(self):
        # 10 normal values at 200, one huge outlier at 2000 — trimmed out.
        offsets = [200.0] * 10 + [2000.0]
        expected = _expected_offset_minutes(offsets, percentile=90, min_history=10)
        assert expected == pytest.approx(200.0)


class TestIsAlertExcludedDag:
    def test_matches_quintoml_namespace(self):
        assert _is_alert_excluded_dag(_QUINTOML_DAG, _CONFIG) is True

    def test_keeps_regular_bietlejuice_dag(self):
        assert _is_alert_excluded_dag(_STANDARD_DAG, _CONFIG) is False

    @pytest.mark.parametrize(
        "dag_id",
        [
            "wonka.user_most_viewed_source",
            "wonka_freshness_check",
            "bietlejuice.enrich_emlio",
            "bietlejuice.evidently_ml_monitor",
        ],
    )
    def test_matches_mlops_owned_dags(self, dag_id):
        assert _is_alert_excluded_dag(dag_id, _CONFIG) is True

    def test_keeps_lookalike_bietlejuice_dag(self):
        assert (
            _is_alert_excluded_dag(
                "bietlejuice.collections_score_batch_inference", _CONFIG
            )
            is False
        )


class TestDropAlertExcludedEntries:
    def test_drops_quintoml_ledger_entries(self):
        ledger = {
            f"{_QUINTOML_DAG}|r1": {"dag_id": _QUINTOML_DAG, "run_id": "r1"},
            f"{_STANDARD_DAG}|r2": {"dag_id": _STANDARD_DAG, "run_id": "r2"},
        }
        _drop_alert_excluded_entries(ledger, _CONFIG)
        assert list(ledger) == [f"{_STANDARD_DAG}|r2"]


class TestIsSlaCandidate:
    def test_excludes_self(self):
        assert _is_sla_candidate(DAG_ID, "Dataset", _SLA_CONFIG) is False

    def test_excludes_null_schedule(self):
        assert _is_sla_candidate("bietlejuice.x", None, _SLA_CONFIG) is False
        assert _is_sla_candidate("bietlejuice.x", "null", _SLA_CONFIG) is False

    def test_excludes_migration_prefix(self):
        assert (
            _is_sla_candidate(
                "migration_compare_people__enrich_pin", "Dataset", _SLA_CONFIG
            )
            is False
        )
        assert (
            _is_sla_candidate("bietlejuice.migration_emr_foo", "0 1 * * *", _SLA_CONFIG)
            is False
        )

    def test_excludes_validation_suffix(self):
        assert (
            _is_sla_candidate(
                "bietlejuice.ada_crawls__validation", "Dataset", _SLA_CONFIG
            )
            is False
        )

    def test_excludes_quintoml_namespace(self):
        assert _is_sla_candidate(_QUINTOML_DAG, "Dataset", _SLA_CONFIG) is False

    def test_keeps_regular_dataset_dag(self):
        assert (
            _is_sla_candidate("bietlejuice.enrich_region", "Dataset", _SLA_CONFIG)
            is True
        )


class TestSelectSlaRoots:
    def test_enrich_region_shaped_fixture(self):
        # core_region + gsheets succeeded; enrich_region late; dw_region late downstream.
        late = {
            "bietlejuice.enrich_region",
            "bietlejuice.dw_region",
            "bietlejuice.dw_user",
        }
        upstream = {
            "bietlejuice.enrich_region": {
                "bietlejuice.core_region",
                "bietlejuice.gsheets_for_rent",
            },
            "bietlejuice.dw_region": {"bietlejuice.enrich_region"},
            "bietlejuice.dw_user": {
                "bietlejuice.enrich_region",
                "bietlejuice.dw_region",
            },
        }
        succeeded = {"bietlejuice.core_region", "bietlejuice.gsheets_for_rent"}
        roots, suppressed, used_fallback = _select_sla_roots(
            late, upstream_index=upstream, succeeded_this_cycle=succeeded
        )
        assert roots == ["bietlejuice.enrich_region"]
        assert suppressed == 2
        assert used_fallback is False

    def test_prefers_confirmed_root_over_late_descendants(self):
        # Two independent late DAGs; only one has all upstreams confirmed.
        late = {"bietlejuice.enrich_region", "bietlejuice.enrich_other"}
        upstream = {
            "bietlejuice.enrich_region": {"bietlejuice.core_region"},
            "bietlejuice.enrich_other": {"bietlejuice.core_other"},
        }
        roots, suppressed, used_fallback = _select_sla_roots(
            late,
            upstream_index=upstream,
            succeeded_this_cycle={"bietlejuice.core_region"},
        )
        assert roots == ["bietlejuice.enrich_region"]
        assert suppressed == 1
        assert used_fallback is False

    def test_non_candidate_upstream_does_not_block(self):
        # A paused / excluded upstream can never succeed this cycle, so requiring it
        # would make enrich_region permanently unalertable.
        late = {"bietlejuice.enrich_region"}
        upstream = {
            "bietlejuice.enrich_region": {
                "bietlejuice.core_region",
                "bietlejuice.paused_upstream",
            }
        }
        roots, suppressed, used_fallback = _select_sla_roots(
            late,
            upstream_index=upstream,
            succeeded_this_cycle={"bietlejuice.core_region"},
            expected_this_cycle={
                "bietlejuice.enrich_region",
                "bietlejuice.core_region",
            },
        )
        assert roots == ["bietlejuice.enrich_region"]
        assert used_fallback is False
        assert suppressed == 0

    def test_falls_back_to_late_set_tops_instead_of_going_silent(self):
        # No late DAG has all expected upstreams confirmed (the true root is invisible:
        # thin history). Reporting the top of the late subgraph beats zero alerts.
        late = {"bietlejuice.enrich_region", "bietlejuice.dw_region"}
        upstream = {
            "bietlejuice.enrich_region": {"bietlejuice.core_region"},
            "bietlejuice.dw_region": {"bietlejuice.enrich_region"},
        }
        roots, suppressed, used_fallback = _select_sla_roots(
            late,
            upstream_index=upstream,
            succeeded_this_cycle=set(),
            expected_this_cycle={
                "bietlejuice.enrich_region",
                "bietlejuice.dw_region",
                "bietlejuice.core_region",
            },
        )
        assert roots == ["bietlejuice.enrich_region"]
        assert suppressed == 1
        assert used_fallback is True


class TestEvaluateSlaMissingRuns:
    def _history_for_offsets(self, dag_id, offsets_minutes, hhmm="20:55"):
        """Build history rows: first starts at each offset for the last N cycles."""
        rows = []
        # Pick a fixed "now" deep into a cycle so due_at can fire.
        now = datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc)
        current_anchor = _cycle_anchor(now, hhmm=hhmm)
        for i, offset in enumerate(offsets_minutes):
            # Place history in prior cycles (not the current one).
            anchor = current_anchor - timedelta(days=i + 1)
            start = anchor + timedelta(minutes=offset)
            rows.append(
                SimpleNamespace(dag_id=dag_id, start_date=start, state="success")
            )
        return now, rows

    def test_alerts_root_past_due(self):
        now, history = self._history_for_offsets(
            "bietlejuice.enrich_region", [230.0] * 12
        )
        # Upstream succeeded this cycle.
        cycle = _cycle_anchor(now, hhmm="20:55")
        history.extend(
            [
                SimpleNamespace(
                    dag_id="bietlejuice.core_region",
                    start_date=cycle + timedelta(minutes=100),
                    state="success",
                ),
                SimpleNamespace(
                    dag_id="bietlejuice.gsheets_for_rent",
                    start_date=cycle + timedelta(minutes=80),
                    state="success",
                ),
            ]
        )
        upstream = {
            "bietlejuice.enrich_region": {
                "bietlejuice.core_region",
                "bietlejuice.gsheets_for_rent",
            }
        }
        findings = _evaluate_sla_missing_runs(
            ["bietlejuice.enrich_region"],
            history,
            now=now,
            config=_SLA_CONFIG,
            upstream_index=upstream,
            downstream_index={},
        )
        assert len(findings) == 1
        f = findings[0]
        assert f["kind"] == _KIND_MISSING_RUN
        assert f["dag_id"] == "bietlejuice.enrich_region"
        assert f["tier"] == "standard"
        assert f["run_id"].startswith("sla::")
        assert f["late_by_s"] > 0

    def test_expected_upstream_outside_candidates_blocks_confirmation(self):
        now, history = self._history_for_offsets(
            "bietlejuice.enrich_region", [230.0] * 12
        )
        upstream = {"bietlejuice.enrich_region": {"bietlejuice.core_region"}}
        # The upstream is eligible this cycle but has not succeeded, and it is not
        # among the evaluated candidates (as happens under only_dags).
        findings = _evaluate_sla_missing_runs(
            ["bietlejuice.enrich_region"],
            history,
            now=now,
            config=_SLA_CONFIG,
            upstream_index=upstream,
            downstream_index={},
            expected_dag_ids={
                "bietlejuice.enrich_region",
                "bietlejuice.core_region",
            },
        )
        assert len(findings) == 1
        assert findings[0]["root_is_fallback"] is True

    def test_skips_when_already_started(self):
        now, history = self._history_for_offsets(
            "bietlejuice.enrich_region", [230.0] * 12
        )
        cycle = _cycle_anchor(now, hhmm="20:55")
        history.append(
            SimpleNamespace(
                dag_id="bietlejuice.enrich_region",
                start_date=cycle + timedelta(minutes=200),
                state="running",
            )
        )
        findings = _evaluate_sla_missing_runs(
            ["bietlejuice.enrich_region"],
            history,
            now=now,
            config=_SLA_CONFIG,
            upstream_index={},
            downstream_index={},
        )
        assert findings == []

    def test_skips_when_disabled(self):
        now, history = self._history_for_offsets(
            "bietlejuice.enrich_region", [230.0] * 12
        )
        config = {**_SLA_CONFIG, "sla_enabled": False}
        assert (
            _evaluate_sla_missing_runs(
                ["bietlejuice.enrich_region"],
                history,
                now=now,
                config=config,
                upstream_index={},
                downstream_index={},
            )
            == []
        )

    def test_grace_keeps_within_window_quiet(self):
        # expected ~230m, grace 60 → due at ~290m into cycle.
        # now at 250m into cycle → not yet due.
        hhmm = "20:55"
        now = datetime(2026, 7, 25, 3, 45, tzinfo=timezone.utc)  # ~230m into cycle
        cycle = _cycle_anchor(now, hhmm=hhmm)
        history = []
        for i in range(12):
            anchor = cycle - timedelta(days=i + 1)
            history.append(
                SimpleNamespace(
                    dag_id="bietlejuice.enrich_region",
                    start_date=anchor + timedelta(minutes=230),
                    state="success",
                )
            )
        findings = _evaluate_sla_missing_runs(
            ["bietlejuice.enrich_region"],
            history,
            now=now,
            config=_SLA_CONFIG,
            upstream_index={},
            downstream_index={},
        )
        assert findings == []


class TestEvaluateDeadlineMisses:
    _CYCLE_START = datetime(2026, 9, 16, 23, 55, tzinfo=timezone.utc)
    _DEADLINES = {_CRITICAL_DAG: "10:00"}
    _HHMM = "20:55"

    def test_now_before_due_returns_empty(self):
        now = datetime(2026, 9, 17, 9, 0, tzinfo=timezone.utc)
        findings = _evaluate_deadline_misses(
            self._DEADLINES,
            [],
            now=now,
            cycle_start=self._CYCLE_START,
            hhmm=self._HHMM,
        )
        assert findings == []

    def test_now_after_due_without_success_yields_finding(self):
        now = datetime(2026, 9, 17, 14, 0, tzinfo=timezone.utc)
        findings = _evaluate_deadline_misses(
            self._DEADLINES,
            [],
            now=now,
            cycle_start=self._CYCLE_START,
            hhmm=self._HHMM,
        )
        assert len(findings) == 1
        f = findings[0]
        assert f["kind"] == _KIND_DEADLINE_MISS
        assert f["tier"] == "standard"
        assert f["run_id"].startswith("deadline::")
        assert f["deadline_localtime"] == "10:00"
        assert f["late_by_s"] > 0

    def test_now_after_due_with_successful_run_in_cycle_returns_empty(self):
        now = datetime(2026, 9, 17, 14, 0, tzinfo=timezone.utc)
        history = [
            SimpleNamespace(
                dag_id=_CRITICAL_DAG,
                start_date=datetime(2026, 9, 17, 2, 0, tzinfo=timezone.utc),
                state="success",
            )
        ]
        findings = _evaluate_deadline_misses(
            self._DEADLINES,
            history,
            now=now,
            cycle_start=self._CYCLE_START,
            hhmm=self._HHMM,
        )
        assert findings == []

    def test_now_after_due_with_emitted_dag_returns_empty(self):
        now = datetime(2026, 9, 17, 14, 0, tzinfo=timezone.utc)
        findings = _evaluate_deadline_misses(
            self._DEADLINES,
            [],
            now=now,
            cycle_start=self._CYCLE_START,
            hhmm=self._HHMM,
            emitted={_CRITICAL_DAG},
        )
        assert findings == []


class TestSlaMessagesAndLedger:
    def test_missing_run_initial_text(self):
        entry = {
            "kind": _KIND_MISSING_RUN,
            "dag_id": "bietlejuice.enrich_region",
            "run_id": "sla::2026-07-24T23:55:00+00:00",
            "owner": "Data ForRent",
            "due_at": "2026-07-25T04:45:00+00:00",
            "expected_start": "2026-07-25T03:45:00+00:00",
            "grace_minutes": 60,
            "percentile": 90,
            "history_count": 14,
            "lookback_days": 14,
            "impacted_dw_dags": ["bietlejuice.dw_region"],
            "also_waiting_count": 319,
        }
        text = _missing_run_initial_text(entry, 4320)
        assert "has not started" in text
        assert "Data ForRent" in text
        assert "Late by: 1h12m (due 04:45 UTC)" in text
        assert "Expected by:" not in text
        assert "• Impacted DW (1): dw_region · also waiting: 319" in text
        assert "Also waiting downstream" not in text
        assert "Trigger:" not in text
        assert "Tracking until it starts." not in text
        assert "Attribution" not in text

    def test_missing_run_initial_text_omits_unconfirmed_root(self):
        entry = {
            "kind": _KIND_MISSING_RUN,
            "dag_id": "bietlejuice.enrich_region",
            "run_id": "sla::2026-07-24T23:55:00+00:00",
            "owner": "Data ForRent",
            "due_at": "2026-07-25T04:45:00+00:00",
            "expected_start": "2026-07-25T03:45:00+00:00",
            "grace_minutes": 60,
            "percentile": 90,
            "history_count": 14,
            "lookback_days": 14,
            "impacted_dw_dags": [],
            "also_waiting_count": 0,
            "late_count": 12,
            "root_is_fallback": True,
        }
        text = _missing_run_initial_text(entry, 4320)
        assert "Attribution" not in text
        assert "• Impacted DW: none" in text

    def test_missing_run_initial_text_merges_also_waiting_when_no_dw(self):
        entry = {
            "kind": _KIND_MISSING_RUN,
            "dag_id": "bietlejuice.enrich_region",
            "owner": "Data ForRent",
            "due_at": "2026-07-25T04:45:00+00:00",
            "impacted_dw_dags": [],
            "also_waiting_count": 12,
        }
        text = _missing_run_initial_text(entry, 3600)
        assert "• Impacted DW: none · also waiting: 12" in text
        assert "Also waiting downstream" not in text

    def test_missing_run_update_text_keeps_also_waiting_separate(self):
        entry = {
            "kind": _KIND_MISSING_RUN,
            "dag_id": "bietlejuice.enrich_region",
            "owner": "Data ForRent",
            "also_waiting_count": 12,
        }
        text = _missing_run_update_text(entry, 7200, also_waiting=12)
        assert "still has not started" in text
        assert "Late by: 2h" in text
        assert "• Also waiting downstream: 12 DAG(s)" in text
        assert "Impacted DW" not in text
        assert "due " not in text

    def test_missing_run_started_text(self):
        entry = {
            "kind": _KIND_MISSING_RUN,
            "dag_id": "bietlejuice.enrich_region",
            "owner": "Data ForRent",
        }
        text = _missing_run_started_text(
            entry,
            started_at=datetime(2026, 7, 25, 12, 33, tzinfo=timezone.utc),
            late_by_s=28080,
        )
        assert "started at 12:33 UTC" in text
        assert "was flagged" not in text

    def test_normalize_ledger_defaults_kind(self):
        raw = {
            "bietlejuice.x|run_1": "2026-07-25T00:00:00+00:00",
            "bietlejuice.y|sla::2026-07-24T23:55:00+00:00": {},
        }
        ledger = _normalize_ledger(raw)
        assert ledger["bietlejuice.x|run_1"]["kind"] == _KIND_SLOW
        assert (
            ledger["bietlejuice.y|sla::2026-07-24T23:55:00+00:00"]["kind"]
            == _KIND_MISSING_RUN
        )

    def test_entry_from_missing_run_finding(self):
        finding = {
            "kind": _KIND_MISSING_RUN,
            "dag_id": "bietlejuice.enrich_region",
            "run_id": _sla_run_id(datetime(2026, 7, 24, 23, 55, tzinfo=timezone.utc)),
            "tier": "standard",
            "cycle_anchor": "2026-07-24T23:55:00+00:00",
            "due_at": "2026-07-25T04:45:00+00:00",
            "expected_start": "2026-07-25T03:45:00+00:00",
            "expected_offset_minutes": 230.0,
            "grace_minutes": 60,
            "percentile": 90,
            "history_count": 14,
            "lookback_days": 14,
            "also_waiting_count": 5,
            "late_count": 6,
            "root_is_fallback": True,
            "impacted_dw_dags": [],
            "owner": "Data ForRent",
        }
        entry = _entry_from_finding(finding, first_alert_ts="ts")
        assert entry["kind"] == _KIND_MISSING_RUN
        assert entry["cycle_anchor"] == "2026-07-24T23:55:00+00:00"
        assert entry["late_count"] == 6
        assert entry["root_is_fallback"] is True
        assert "baseline_s" not in entry

    def test_cycle_rollover_drops_sla_entry(self):
        old_anchor = "2026-07-23T23:55:00+00:00"
        key = f"bietlejuice.enrich_region|sla::{old_anchor}"
        ledger = {
            key: {
                "kind": _KIND_MISSING_RUN,
                "dag_id": "bietlejuice.enrich_region",
                "run_id": f"sla::{old_anchor}",
                "cycle_anchor": old_anchor,
                "due_at": "2026-07-24T04:45:00+00:00",
                "owner": "Data ForRent",
            }
        }
        now = datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc)
        with mock.patch(f"{_MODULE}._post_gchat", return_value=True) as post:
            _apply_sla_follow_up(ledger, {}, None, now, _SLA_CONFIG)
        assert key not in ledger
        post.assert_not_called()

    def test_started_closes_sla_entry(self):
        anchor = "2026-07-24T23:55:00+00:00"
        key = f"bietlejuice.enrich_region|sla::{anchor}"
        ledger = {
            key: {
                "kind": _KIND_MISSING_RUN,
                "dag_id": "bietlejuice.enrich_region",
                "run_id": f"sla::{anchor}",
                "cycle_anchor": anchor,
                "due_at": "2026-07-25T04:45:00+00:00",
                "owner": "Data ForRent",
            }
        }
        now = datetime(2026, 7, 25, 12, 33, tzinfo=timezone.utc)
        started = {
            "bietlejuice.enrich_region": datetime(
                2026, 7, 25, 12, 33, tzinfo=timezone.utc
            )
        }
        with mock.patch(f"{_MODULE}._post_gchat", return_value=True) as post:
            _apply_sla_follow_up(ledger, started, "http://hook", now, _SLA_CONFIG)
        assert key not in ledger
        assert post.call_count == 1
        assert "started at" in post.call_args.args[1]

    def test_deadline_miss_succeeded_closes_entry(self):
        now = datetime(2026, 9, 17, 12, 0, tzinfo=timezone.utc)
        hhmm = _resolve_anchor_hhmm(_SLA_CONFIG.get("sla_cycle_anchor_local_time"))
        anchor_dt = _cycle_anchor(now, hhmm=hhmm)
        cycle_anchor = anchor_dt.isoformat()
        run_id = _deadline_run_id(anchor_dt)
        key = f"{_CRITICAL_DAG}|{run_id}"
        due_at = datetime(2026, 9, 17, 10, 0, tzinfo=timezone.utc)
        ledger = {
            key: {
                "kind": _KIND_DEADLINE_MISS,
                "dag_id": _CRITICAL_DAG,
                "run_id": run_id,
                "cycle_anchor": cycle_anchor,
                "due_at": due_at.isoformat(),
                "deadline_localtime": "10:00",
                "owner": "Data ForRent",
            }
        }
        succeeded = {_CRITICAL_DAG: datetime(2026, 9, 17, 10, 30, tzinfo=timezone.utc)}
        with mock.patch(f"{_MODULE}._post_gchat", return_value=True) as post:
            _apply_sla_follow_up(
                ledger, {}, "http://hook", now, _SLA_CONFIG, succeeded_by_dag=succeeded
            )
        assert key not in ledger
        assert post.call_count == 1
        assert "finished at" in post.call_args.args[1]

    def test_deadline_miss_not_succeeded_keeps_entry_and_sends_update(self):
        now = datetime(2026, 9, 17, 12, 0, tzinfo=timezone.utc)
        hhmm = _resolve_anchor_hhmm(_SLA_CONFIG.get("sla_cycle_anchor_local_time"))
        anchor_dt = _cycle_anchor(now, hhmm=hhmm)
        cycle_anchor = anchor_dt.isoformat()
        run_id = _deadline_run_id(anchor_dt)
        key = f"{_CRITICAL_DAG}|{run_id}"
        due_at = datetime(2026, 9, 17, 10, 0, tzinfo=timezone.utc)
        ledger = {
            key: {
                "kind": _KIND_DEADLINE_MISS,
                "dag_id": _CRITICAL_DAG,
                "run_id": run_id,
                "cycle_anchor": cycle_anchor,
                "due_at": due_at.isoformat(),
                "deadline_localtime": "10:00",
                "owner": "Data ForRent",
            }
        }
        with mock.patch(f"{_MODULE}._post_gchat", return_value=True) as post:
            _apply_sla_follow_up(ledger, {}, "http://hook", now, _SLA_CONFIG)
        assert key in ledger
        assert post.call_count == 1
        assert "still not finished" in post.call_args.args[1]

    def test_queries_are_task_instance_free(self):
        assert "task_instance" not in str(_SLA_CANDIDATES_QUERY)
        assert "task_instance" not in str(_SLA_HISTORY_QUERY)

    def test_synthetic_missing_run_findings(self):
        findings = _synthetic_missing_run_findings(
            _SLA_CONFIG, ["bietlejuice.__simulated_missing__"]
        )
        assert findings[0]["kind"] == _KIND_MISSING_RUN
        assert findings[0]["tier"] == "standard"


class TestAlsoWaitingAndUpstreamIndex:
    def test_also_waiting_counts_late_downstream(self):
        late = {
            "bietlejuice.enrich_region",
            "bietlejuice.dw_region",
            "bietlejuice.dw_user",
            "bietlejuice.unrelated",
        }
        downstream_index = {
            "bietlejuice.enrich_region": {"bietlejuice.dw_region"},
            "bietlejuice.dw_region": {"bietlejuice.dw_user"},
        }
        assert (
            _also_waiting_count("bietlejuice.enrich_region", late, downstream_index)
            == 2
        )

    def test_build_upstream_index_flattens_any_all(self):
        deps = {
            "bietlejuice.enrich_region": {
                "any": [
                    {
                        "all": [
                            "bietlejuice.core_region:load-core-region:first-run-of-day",
                            "bietlejuice.gsheets_for_rent:done-clean-auxiliary-region:first-run-of-day",
                        ]
                    },
                    {
                        "any": [
                            "bietlejuice.core_region:load-core-region:reprocessing",
                        ]
                    },
                ]
            }
        }
        index = _build_upstream_index(deps)
        assert index["bietlejuice.enrich_region"] == {
            "bietlejuice.core_region",
            "bietlejuice.gsheets_for_rent",
        }


class TestResolveAnchorHhmm:
    def test_valid_passthrough(self):
        assert _resolve_anchor_hhmm("20:55") == "20:55"
        assert _resolve_anchor_hhmm("9:05") == "09:05"

    def test_invalid_falls_back(self):
        assert _resolve_anchor_hhmm("not-a-time") == "20:55"
        assert _resolve_anchor_hhmm("25:99") == "20:55"
        assert _resolve_anchor_hhmm("") == "20:55"
        assert _resolve_anchor_hhmm(None) == "20:55"


class TestLoadUpstreamIndexSafe:
    def test_returns_none_on_read_failure(self):
        with mock.patch(
            f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
            side_effect=RuntimeError("boom"),
        ):
            assert _load_upstream_index_safe() is None

    def test_returns_none_when_deps_not_a_dict(self):
        with mock.patch(
            f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
            return_value=["not", "a", "dict"],
        ):
            assert _load_upstream_index_safe() is None

    def test_returns_empty_dict_for_empty_deps(self):
        with mock.patch(
            f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
            return_value={},
        ):
            assert _load_upstream_index_safe() == {}


class TestCollectSlaFindingsFailClosed:
    def test_skips_when_upstream_index_unavailable(self):
        with (
            mock.patch(f"{_MODULE}._load_upstream_index_safe", return_value=None),
            mock.patch(f"{_MODULE}._fetch_sla_history") as history,
            mock.patch(f"{_MODULE}._evaluate_sla_missing_runs") as evaluate,
        ):
            assert (
                _collect_sla_findings(
                    mock.Mock(),
                    _SLA_CONFIG,
                    datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc),
                    {},
                    candidates=["bietlejuice.enrich_region"],
                )
                == []
            )
            history.assert_not_called()
            evaluate.assert_not_called()

    def test_only_dags_narrows_evaluation_but_not_expected_upstreams(self):
        candidates = [
            "bietlejuice.enrich_region",
            "bietlejuice.clean_region",
            "bietlejuice.dw_region",
        ]
        with (
            mock.patch(f"{_MODULE}._load_upstream_index_safe", return_value={}),
            mock.patch(f"{_MODULE}._fetch_sla_history", return_value=[]),
            mock.patch(
                f"{_MODULE}._evaluate_sla_missing_runs", return_value=[]
            ) as evaluate,
        ):
            _collect_sla_findings(
                mock.Mock(),
                _SLA_CONFIG,
                datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc),
                {},
                candidates=list(candidates),
                only_dags=["bietlejuice.dw_region"],
            )
        args, kwargs = evaluate.call_args
        assert args[0] == ["bietlejuice.dw_region"]
        assert kwargs["expected_dag_ids"] == set(candidates)


class TestFollowUpTrackedRunsSlaGuards:
    def _sla_ledger(self):
        anchor = "2026-07-24T23:55:00+00:00"
        key = f"bietlejuice.enrich_region|sla::{anchor}"
        return key, {
            key: {
                "kind": _KIND_MISSING_RUN,
                "dag_id": "bietlejuice.enrich_region",
                "run_id": f"sla::{anchor}",
                "cycle_anchor": anchor,
                "due_at": "2026-07-25T04:45:00+00:00",
                "owner": "Data ForRent",
            }
        }

    def test_sla_disabled_drops_ledger_without_chat(self):
        key, ledger = self._sla_ledger()
        config = {**_SLA_CONFIG, "sla_enabled": False}
        now = datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc)
        with (
            mock.patch(f"{_MODULE}._post_gchat", return_value=True) as post,
            mock.patch(f"{_MODULE}._fetch_sla_started") as started,
        ):
            _follow_up_tracked_runs(
                mock.Mock(),
                ledger,
                "http://hook",
                now,
                {},
                config,
                sla_candidates=["bietlejuice.enrich_region"],
            )
        assert key not in ledger
        post.assert_not_called()
        started.assert_not_called()

    def test_paused_or_ineligible_dag_drops_without_chat(self):
        key, ledger = self._sla_ledger()
        now = datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc)
        with (
            mock.patch(f"{_MODULE}._post_gchat", return_value=True) as post,
            mock.patch(f"{_MODULE}._fetch_sla_started") as started,
        ):
            _follow_up_tracked_runs(
                mock.Mock(),
                ledger,
                "http://hook",
                now,
                {},
                _SLA_CONFIG,
                sla_candidates=[],
            )
        assert key not in ledger
        post.assert_not_called()
        started.assert_not_called()

    def test_eligible_dag_still_gets_follow_up(self):
        key, ledger = self._sla_ledger()
        now = datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc)
        with (
            mock.patch(f"{_MODULE}._post_gchat", return_value=True) as post,
            mock.patch(f"{_MODULE}._fetch_sla_started", return_value={}),
        ):
            _follow_up_tracked_runs(
                mock.Mock(),
                ledger,
                "http://hook",
                now,
                {},
                _SLA_CONFIG,
                sla_candidates=["bietlejuice.enrich_region"],
            )
        assert key in ledger
        assert post.call_count == 1


class TestMonitorEnrichesSlaFindings:
    def test_production_path_enriches_sla_findings(self):
        sla_finding = {
            "kind": _KIND_MISSING_RUN,
            "dag_id": "bietlejuice.enrich_region",
            "run_id": "sla::2026-07-24T23:55:00+00:00",
            "tier": "standard",
            "late_by_s": 100.0,
            "elapsed_s": 100.0,
            "due_at": "2026-07-25T04:45:00+00:00",
            "expected_start": "2026-07-25T03:45:00+00:00",
            "grace_minutes": 60,
            "percentile": 90,
            "history_count": 14,
            "lookback_days": 14,
            "also_waiting_count": 0,
        }
        enrich_calls = []

        def _capture_enrich(findings, _index):
            enrich_calls.append([dict(f) for f in findings])
            for f in findings:
                f["impacted_dw_dags"] = ["bietlejuice.dw_region"]
                f["impacted_dw_count"] = 1

        with (
            mock.patch(f"{_MODULE}.ConfigurationService") as mock_cfg,
            mock.patch(f"{_MODULE}.Variable") as mock_var,
            mock.patch(f"{_MODULE}._load_downstream_index_safe", return_value={}),
            mock.patch(f"{_MODULE}._fetch_running_runs", return_value=[]),
            mock.patch(
                f"{_MODULE}._collect_sla_findings", return_value=[dict(sla_finding)]
            ),
            mock.patch(
                f"{_MODULE}._enrich_findings_with_dw_impact",
                side_effect=_capture_enrich,
            ),
            mock.patch(f"{_MODULE}._fetch_run_states", return_value={}),
            mock.patch(f"{_MODULE}._post_gchat", return_value=True),
            mock.patch(f"{_MODULE}._send_jira_alert", return_value=True),
        ):
            mock_cfg.return_value.get_config.side_effect = _config_get
            mock_var.get.side_effect = _variable_get_factory(environment="forno")
            monitor_dag_runtimes(session=_db_session(), run_conf={})

        assert any(
            calls and calls[0].get("kind") == _KIND_MISSING_RUN
            for calls in enrich_calls
        )


class TestMonitorPagesCriticalMissingRun:
    _CYCLE = datetime(2026, 8, 16, 23, 55, tzinfo=timezone.utc)

    def _sla_finding(self, dag_id):
        return {
            "kind": _KIND_MISSING_RUN,
            "dag_id": dag_id,
            "run_id": _sla_run_id(self._CYCLE),
            "tier": "standard",
            "late_by_s": 3600.0,
            "elapsed_s": 3600.0,
            "due_at": "2026-08-17T04:55:00+00:00",
            "expected_start": "2026-08-17T03:55:00+00:00",
            "grace_minutes": 60,
            "percentile": 90,
            "history_count": 14,
            "lookback_days": 14,
            "also_waiting_count": 0,
        }

    def test_critical_member_pages_jira_and_tracks(self):
        sla_run_id = _sla_run_id(self._CYCLE)
        finding = self._sla_finding(_CRITICAL_DAG)
        with (
            mock.patch(f"{_MODULE}.ConfigurationService") as mock_cfg,
            mock.patch(f"{_MODULE}.Variable") as mock_var,
            mock.patch(f"{_MODULE}._load_downstream_index_safe", return_value={}),
            mock.patch(f"{_MODULE}._fetch_running_runs", return_value=[]),
            mock.patch(
                f"{_MODULE}._collect_sla_findings", return_value=[dict(finding)]
            ),
            mock.patch(f"{_MODULE}._fetch_run_states", return_value={}),
            mock.patch(f"{_MODULE}._post_gchat", return_value=True) as mock_post,
            mock.patch(f"{_MODULE}._send_jira_alert", return_value=True) as mock_jira,
        ):
            mock_cfg.return_value.get_config.side_effect = _config_get
            mock_var.get.side_effect = _variable_get_factory(environment="prod")
            monitor_dag_runtimes(session=_db_session(), run_conf={})

        mock_jira.assert_called_once()
        passed = mock_jira.call_args.args[0]
        assert passed["tier"] == "critical"
        assert passed["kind"] == _KIND_MISSING_RUN
        mock_post.assert_called_once()
        saved = _saved_ledger(mock_var)
        assert saved[f"{_CRITICAL_DAG}|{sla_run_id}"]["tier"] == "critical"

    def test_upstream_missing_run_is_chat_only(self):
        finding = self._sla_finding("bietlejuice.enrich_region")
        index = {"bietlejuice.enrich_region": {_CRITICAL_DAG}}
        with (
            mock.patch(f"{_MODULE}.ConfigurationService") as mock_cfg,
            mock.patch(f"{_MODULE}.Variable") as mock_var,
            mock.patch(f"{_MODULE}._load_downstream_index_safe", return_value=index),
            mock.patch(f"{_MODULE}._fetch_running_runs", return_value=[]),
            mock.patch(
                f"{_MODULE}._collect_sla_findings", return_value=[dict(finding)]
            ),
            mock.patch(f"{_MODULE}._fetch_run_states", return_value={}),
            mock.patch(f"{_MODULE}._post_gchat", return_value=True) as mock_post,
            mock.patch(f"{_MODULE}._send_jira_alert", return_value=True) as mock_jira,
        ):
            mock_cfg.return_value.get_config.side_effect = _config_get
            mock_var.get.side_effect = _variable_get_factory(environment="prod")
            monitor_dag_runtimes(session=_db_session(), run_conf={})

        mock_jira.assert_not_called()
        mock_post.assert_called_once()


# --------------------------------------------------------------------------- #
# Live dataset dependency graph
# --------------------------------------------------------------------------- #
def _edge_row(dependent, upstream, uri=None):
    return SimpleNamespace(
        dependent_dag_id=dependent, upstream_dag_id=upstream, uri=uri
    )


def _dataset_row(dag_id, uri, satisfied, producer=None):
    return SimpleNamespace(
        dag_id=dag_id, uri=uri, satisfied=satisfied, producer_dag_id=producer
    )


class TestUnionIndexes:
    def test_all_sources_unavailable_returns_none(self):
        assert _union_indexes(None, None) is None

    def test_empty_but_available_source_returns_empty_dict(self):
        assert _union_indexes({}, None) == {}

    def test_merges_disjoint_and_overlapping_keys(self):
        merged = _union_indexes(
            {"a": {"x"}, "b": {"y"}},
            {"a": {"z"}, "c": {"w"}},
        )
        assert merged == {"a": {"x", "z"}, "b": {"y"}, "c": {"w"}}

    def test_does_not_mutate_inputs(self):
        first = {"a": {"x"}}
        _union_indexes(first, {"a": {"z"}})
        assert first == {"a": {"x"}}


class TestBuildDatasetIndexes:
    def test_none_rows_yield_none_indexes(self):
        assert _build_dataset_indexes(None) == (None, None)

    def test_builds_both_directions(self):
        upstream, downstream = _build_dataset_indexes(
            [
                _edge_row("quintoml.wonka.segmentation", "bietlejuice.dw_contract"),
                _edge_row("bietlejuice.dw_z", "quintoml.wonka.segmentation"),
            ]
        )
        assert upstream == {
            "quintoml.wonka.segmentation": {"bietlejuice.dw_contract"},
            "bietlejuice.dw_z": {"quintoml.wonka.segmentation"},
        }
        assert downstream == {
            "bietlejuice.dw_contract": {"quintoml.wonka.segmentation"},
            "quintoml.wonka.segmentation": {"bietlejuice.dw_z"},
        }

    def test_skips_self_edges_and_blanks(self):
        upstream, downstream = _build_dataset_indexes(
            [
                _edge_row("bietlejuice.a", "bietlejuice.a"),
                _edge_row("bietlejuice.b", None),
                _edge_row(None, "bietlejuice.c"),
            ]
        )
        assert upstream == {}
        assert downstream == {}


class TestGraphSourcesFailureModes:
    def test_upstream_falls_back_to_live_graph_when_yaml_fails(self):
        live = {"quintoml.wonka.segmentation": {"bietlejuice.dw_contract"}}
        with mock.patch(
            f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
            side_effect=RuntimeError("boom"),
        ):
            assert _load_upstream_index_safe(live) == live

    def test_upstream_unions_both_sources(self):
        with mock.patch(
            f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
            return_value={"bietlejuice.dw_region": ["bietlejuice.enrich_region"]},
        ):
            merged = _load_upstream_index_safe(
                {"bietlejuice.dw_region": {"quintoml.wonka.segmentation"}}
            )
        assert merged["bietlejuice.dw_region"] == {
            "bietlejuice.enrich_region",
            "quintoml.wonka.segmentation",
        }

    def test_upstream_none_only_when_both_sources_fail(self):
        with mock.patch(
            f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
            side_effect=RuntimeError("boom"),
        ):
            assert _load_upstream_index_safe(None) is None

    def test_downstream_falls_back_to_live_graph_when_yaml_fails(self):
        live = {"bietlejuice.dw_contract": {"quintoml.wonka.segmentation"}}
        with mock.patch(
            f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
            side_effect=RuntimeError("boom"),
        ):
            assert _load_downstream_index_safe(live) == live

    def test_downstream_none_only_when_both_sources_fail(self):
        with mock.patch(
            f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
            side_effect=RuntimeError("boom"),
        ):
            assert _load_downstream_index_safe(None) is None

    def test_downstream_ignores_non_mapping_yaml_but_keeps_live(self):
        live = {"bietlejuice.dw_contract": {"quintoml.wonka.segmentation"}}
        with mock.patch(
            f"{_MODULE}.BietlejuiceDependencyHelper.read_dependencies",
            return_value=["not", "a", "dict"],
        ):
            assert _load_downstream_index_safe(live) == live


class TestLiveGraphUnblocksQuintomlSuppression:
    """dependencies.yaml has no ``quintoml.*`` dependent keys, so those DAGs always
    self-root; the live dataset edges are the only source that knows their upstreams."""

    _QUINTOML = "quintoml.wonka.contract_collection_segmentation"
    _UPSTREAM = "bietlejuice.dw_contract"

    def _history(self, now):
        cycle = _cycle_anchor(now, hhmm="20:55")
        rows = []
        for dag_id in (self._QUINTOML, self._UPSTREAM):
            for i in range(12):
                anchor = cycle - timedelta(days=i + 1)
                rows.append(
                    SimpleNamespace(
                        dag_id=dag_id,
                        start_date=anchor + timedelta(minutes=230),
                        state="success",
                    )
                )
        return rows

    def _roots(self, upstream_index):
        now = datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc)
        findings = _evaluate_sla_missing_runs(
            [self._QUINTOML, self._UPSTREAM],
            self._history(now),
            now=now,
            config=_SLA_CONFIG,
            upstream_index=upstream_index,
            downstream_index={},
        )
        return {f["dag_id"] for f in findings}

    def test_yaml_only_graph_self_roots_the_quintoml_dag(self):
        assert self._roots({}) == {self._QUINTOML, self._UPSTREAM}

    def test_live_edge_folds_it_under_its_upstream(self):
        upstream, _ = _build_dataset_indexes(
            [_edge_row(self._QUINTOML, self._UPSTREAM)]
        )
        assert self._roots(upstream) == {self._UPSTREAM}


# --------------------------------------------------------------------------- #
# Dataset-satisfaction diagnostics
# --------------------------------------------------------------------------- #
class TestBuildDatasetStatus:
    def test_groups_by_dag_and_uri_and_collects_producers(self):
        status = _build_dataset_status(
            [
                _dataset_row("d", "uri-a", 1, "bietlejuice.p1"),
                _dataset_row("d", "uri-a", 1, "bietlejuice.p2"),
                _dataset_row("d", "uri-b", 0, "bietlejuice.p3"),
                _dataset_row("other", "uri-c", 0, None),
            ]
        )
        assert status["d"]["uri-a"] == {
            "satisfied": True,
            "producers": {"bietlejuice.p1", "bietlejuice.p2"},
        }
        assert status["d"]["uri-b"]["satisfied"] is False
        assert status["other"]["uri-c"]["producers"] == set()

    def test_ignores_rows_without_dag_or_uri(self):
        assert (
            _build_dataset_status(
                [_dataset_row(None, "uri", 1), _dataset_row("d", None, 1)]
            )
            == {}
        )


class TestClassifyDatasetState:
    def test_cron_dag_without_datasets_yields_nothing(self):
        assert (
            _classify_dataset_state(None, emitted_uris=set(), completed_dags=set())
            == {}
        )
        assert (
            _classify_dataset_state({}, emitted_uris=set(), completed_dags=set()) == {}
        )

    def test_all_satisfied_but_no_run_is_a_dropped_event(self):
        datasets = {
            "uri-a": {"satisfied": True, "producers": {"bietlejuice.p1"}},
            "uri-b": {"satisfied": True, "producers": {"bietlejuice.p2"}},
        }
        result = _classify_dataset_state(
            datasets, emitted_uris=set(), completed_dags=set()
        )
        assert result["dataset_verdict"] == _VERDICT_DROPPED_EVENT
        assert result["dataset_satisfied"] == 2
        assert result["dataset_required"] == 2
        assert result["dataset_missing"] == []
        assert result["dataset_ready_missing"] == []

    def test_thirteen_of_fourteen_with_succeeded_producer_is_a_dropped_event(self):
        datasets = {
            f"uri-{i}": {"satisfied": True, "producers": {f"bietlejuice.p{i}"}}
            for i in range(13)
        }
        datasets["uri-missing"] = {
            "satisfied": False,
            "producers": {"bietlejuice.enrich_chatbot"},
        }
        result = _classify_dataset_state(
            datasets, emitted_uris=set(), completed_dags={"bietlejuice.enrich_chatbot"}
        )
        assert result["dataset_verdict"] == _VERDICT_DROPPED_EVENT
        assert result["dataset_satisfied"] == 13
        assert result["dataset_required"] == 14
        assert result["dataset_missing"] == ["uri-missing"]
        assert result["dataset_ready_missing"] == ["uri-missing"]
        assert result["dataset_blocking_dags"] == []

    def test_missing_with_pending_producer_is_waiting_upstream(self):
        datasets = {
            "uri-a": {"satisfied": True, "producers": {"bietlejuice.p1"}},
            "uri-b": {"satisfied": False, "producers": {"bietlejuice.slow_upstream"}},
        }
        result = _classify_dataset_state(
            datasets, emitted_uris=set(), completed_dags={"bietlejuice.p1"}
        )
        assert result["dataset_verdict"] == _VERDICT_WAITING_UPSTREAM
        assert result["dataset_blocking_dags"] == ["bietlejuice.slow_upstream"]
        assert result["dataset_ready_missing"] == []

    def test_any_producer_succeeding_is_enough(self):
        # Airflow satisfies the condition on the first emission, not on all producers.
        datasets = {
            "uri-a": {
                "satisfied": False,
                "producers": {"bietlejuice.p1", "bietlejuice.p2"},
            }
        }
        result = _classify_dataset_state(
            datasets, emitted_uris=set(), completed_dags={"bietlejuice.p1"}
        )
        assert result["dataset_verdict"] == _VERDICT_DROPPED_EVENT

    def test_missing_without_known_producer_is_waiting_with_no_blocker_named(self):
        datasets = {"uri-a": {"satisfied": False, "producers": set()}}
        result = _classify_dataset_state(
            datasets, emitted_uris=set(), completed_dags=set()
        )
        assert result["dataset_verdict"] == _VERDICT_WAITING_UPSTREAM
        assert result["dataset_blocking_dags"] == []


class TestEnrichFindingsWithDatasetState:
    def test_attaches_per_finding_state(self):
        findings = [
            {"dag_id": "bietlejuice.a"},
            {"dag_id": "bietlejuice.cron_only"},
        ]
        _enrich_findings_with_dataset_state(
            findings,
            {
                "bietlejuice.a": {
                    "uri-a": {"satisfied": False, "producers": {"bietlejuice.p1"}}
                }
            },
            emitted_uris=set(),
            completed_dags={"bietlejuice.p1"},
        )
        assert findings[0]["dataset_verdict"] == _VERDICT_DROPPED_EVENT
        assert "dataset_verdict" not in findings[1]

    def test_unavailable_status_leaves_findings_untouched(self):
        findings = [{"dag_id": "bietlejuice.a"}]
        _enrich_findings_with_dataset_state(
            findings, None, emitted_uris=set(), completed_dags=set()
        )
        assert findings == [{"dag_id": "bietlejuice.a"}]


# --------------------------------------------------------------------------- #
# Dataset-aware message rendering
# --------------------------------------------------------------------------- #
class TestMissingRunDatasetMessage:
    _BASE = {
        "kind": _KIND_MISSING_RUN,
        "dag_id": "bietlejuice.enrich_chatbot",
        "run_id": "sla::2026-07-24T23:55:00+00:00",
        "owner": "Data Chatbot",
        "due_at": "2026-07-25T04:45:00+00:00",
        "expected_start": "2026-07-25T03:45:00+00:00",
        "grace_minutes": 60,
        "percentile": 90,
        "history_count": 14,
        "lookback_days": 14,
    }

    def test_dropped_event_names_missing_uri_without_runbook_or_trigger(self):
        entry = {
            **self._BASE,
            "dataset_required": 14,
            "dataset_satisfied": 13,
            "dataset_missing": ["internal_chat:messages:first-run-of-day"],
            "dataset_ready_missing": ["internal_chat:messages:first-run-of-day"],
            "dataset_verdict": _VERDICT_DROPPED_EVENT,
        }
        text = _missing_run_initial_text(entry, 3600)
        assert "• Datasets: 13/14 satisfied" in text
        assert "missing internal_chat:messages:first-run-of-day" in text
        assert "producer already delivered, update never recorded" in text
        assert "• Likely a dropped dataset event (" in text
        assert "docs.google.com" not in text
        assert "Trigger" not in text
        assert "conf=" not in text

    def test_all_satisfied_dropped_event_uses_the_other_cause(self):
        entry = {
            **self._BASE,
            "dataset_required": 19,
            "dataset_satisfied": 19,
            "dataset_missing": [],
            "dataset_ready_missing": [],
            "dataset_verdict": _VERDICT_DROPPED_EVENT,
        }
        text = _missing_run_initial_text(entry, 3600)
        assert "• Datasets: 19/19 satisfied" in text
        assert "missing" not in text.split("• Datasets")[1].split("\n")[0]
        assert "all conditions met, no run created" in text

    def test_waiting_upstream_names_blocker_without_trigger(self):
        entry = {
            **self._BASE,
            "dataset_required": 5,
            "dataset_satisfied": 3,
            "dataset_missing": ["uri-a", "uri-b"],
            "dataset_ready_missing": [],
            "dataset_blocking_dags": ["bietlejuice.slow_upstream"],
            "dataset_verdict": _VERDICT_WAITING_UPSTREAM,
        }
        text = _missing_run_initial_text(entry, 3600)
        assert "• Waiting on: bietlejuice.slow_upstream" in text
        assert "Trigger" not in text
        assert "dropped dataset event" not in text

    def test_cron_dag_message_has_no_dataset_bullets(self):
        text = _missing_run_initial_text(dict(self._BASE), 3600)
        assert "• Datasets:" not in text
        assert "Trigger" not in text

    def test_missing_uri_list_is_capped(self):
        missing = [f"uri-{i}" for i in range(_MISSING_DATASET_LIST_LIMIT + 4)]
        entry = {
            **self._BASE,
            "dataset_required": len(missing),
            "dataset_satisfied": 0,
            "dataset_missing": missing,
            "dataset_ready_missing": [],
            "dataset_blocking_dags": [],
            "dataset_verdict": _VERDICT_WAITING_UPSTREAM,
        }
        text = _missing_run_initial_text(entry, 3600)
        assert "… and 4 more" in text
        assert f"uri-{_MISSING_DATASET_LIST_LIMIT + 3}" not in text

    def test_entry_from_finding_carries_dataset_fields(self):
        finding = {
            **self._BASE,
            "tier": "standard",
            "dataset_required": 14,
            "dataset_satisfied": 13,
            "dataset_missing": ["uri-a"],
            "dataset_ready_missing": ["uri-a"],
            "dataset_blocking_dags": [],
            "dataset_verdict": _VERDICT_DROPPED_EVENT,
        }
        entry = _entry_from_finding(finding)
        assert entry["dataset_verdict"] == _VERDICT_DROPPED_EVENT
        assert entry["dataset_missing"] == ["uri-a"]
        assert entry["dataset_satisfied"] == 13


# --------------------------------------------------------------------------- #
# Closing the alert on real remediation (dataset emission)
# --------------------------------------------------------------------------- #
class TestEmissionClosesMissingRunAlerts:
    _DAG = "bietlejuice.enrich_region"

    def _history(self, now):
        cycle = _cycle_anchor(now, hhmm="20:55")
        return [
            SimpleNamespace(
                dag_id=self._DAG,
                start_date=cycle - timedelta(days=i + 1) + timedelta(minutes=230),
                state="success",
            )
            for i in range(12)
        ]

    def test_emission_suppresses_the_finding(self):
        now = datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc)
        assert (
            _evaluate_sla_missing_runs(
                [self._DAG],
                self._history(now),
                now=now,
                config=_SLA_CONFIG,
                upstream_index={},
                downstream_index={},
                emitted_this_cycle={self._DAG},
            )
            == []
        )

    def test_without_emission_the_finding_still_fires(self):
        now = datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc)
        findings = _evaluate_sla_missing_runs(
            [self._DAG],
            self._history(now),
            now=now,
            config=_SLA_CONFIG,
            upstream_index={},
            downstream_index={},
            emitted_this_cycle=set(),
        )
        assert [f["dag_id"] for f in findings] == [self._DAG]

    def test_upstream_emission_confirms_the_dependent_as_a_root(self):
        now = datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc)
        findings = _evaluate_sla_missing_runs(
            [self._DAG],
            self._history(now),
            now=now,
            config=_SLA_CONFIG,
            upstream_index={self._DAG: {"bietlejuice.core_region"}},
            downstream_index={},
            expected_dag_ids={self._DAG, "bietlejuice.core_region"},
            emitted_this_cycle={"bietlejuice.core_region"},
        )
        assert len(findings) == 1
        assert findings[0]["root_is_fallback"] is False

    def _sla_ledger(self):
        anchor = "2026-07-24T23:55:00+00:00"
        key = f"{self._DAG}|sla::{anchor}"
        return key, {
            key: {
                "kind": _KIND_MISSING_RUN,
                "dag_id": self._DAG,
                "run_id": f"sla::{anchor}",
                "cycle_anchor": anchor,
                "due_at": "2026-07-25T04:45:00+00:00",
                "owner": "Data ForRent",
            }
        }

    def test_follow_up_closes_the_thread_on_emission(self):
        key, ledger = self._sla_ledger()
        now = datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc)
        with (
            mock.patch(f"{_MODULE}._post_gchat", return_value=True) as post,
            mock.patch(f"{_MODULE}._fetch_sla_started", return_value={}),
        ):
            _follow_up_tracked_runs(
                mock.Mock(),
                ledger,
                "http://hook",
                now,
                {},
                _SLA_CONFIG,
                sla_candidates=[self._DAG],
                sla_emitted={self._DAG: now - timedelta(minutes=5)},
            )
        assert key not in ledger
        assert "started at" in post.call_args.args[1]

    def test_bare_manual_run_without_emission_does_not_close(self):
        # A manual trigger with no run_type resolves to TEST_RUN: it is excluded from
        # _SLA_STARTED_QUERY and emits nothing, so downstream stays blocked and the
        # alert must keep repeating.
        key, ledger = self._sla_ledger()
        now = datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc)
        with (
            mock.patch(f"{_MODULE}._post_gchat", return_value=True) as post,
            mock.patch(f"{_MODULE}._fetch_sla_started", return_value={}),
        ):
            _follow_up_tracked_runs(
                mock.Mock(),
                ledger,
                "http://hook",
                now,
                {},
                _SLA_CONFIG,
                sla_candidates=[self._DAG],
                sla_emitted={},
            )
        assert key in ledger
        assert "still has not started" in post.call_args.args[1]

    def test_history_baseline_query_stays_manual_free(self):
        # Emission only feeds "started this cycle"; the P90 baseline must keep using
        # automatic runs only, or manual reruns would drift the expected offset.
        assert "scheduled" in str(_SLA_HISTORY_QUERY)
        assert "dataset_event" not in str(_SLA_HISTORY_QUERY)


# --------------------------------------------------------------------------- #
# Dataset-aware DB access
# --------------------------------------------------------------------------- #
class TestDatasetFetchers:
    def test_satisfaction_returns_empty_for_no_dag_ids(self):
        session = mock.Mock()
        assert _fetch_dataset_satisfaction(session, []) == {}
        session.execute.assert_not_called()

    def test_satisfaction_returns_none_on_db_error(self):
        session = mock.Mock()
        session.execute.side_effect = RuntimeError("no such table")
        assert _fetch_dataset_satisfaction(session, ["bietlejuice.a"]) is None

    def test_satisfaction_builds_status(self):
        session = mock.Mock()
        session.execute.return_value.fetchall.return_value = [
            _dataset_row("bietlejuice.a", "uri-a", 0, "bietlejuice.p1")
        ]
        status = _fetch_dataset_satisfaction(session, ["bietlejuice.a"])
        assert status["bietlejuice.a"]["uri-a"]["producers"] == {"bietlejuice.p1"}

    def test_emitted_degrades_to_empty_on_db_error(self):
        session = mock.Mock()
        session.execute.side_effect = RuntimeError("no such table")
        assert (
            _fetch_sla_emitted(
                session, datetime(2026, 7, 24, 23, 55, tzinfo=timezone.utc)
            )
            == {}
        )

    def test_emitted_maps_dag_to_first_emit(self):
        first_emit = datetime(2026, 7, 25, 4, 55, tzinfo=timezone.utc)
        session = mock.Mock()
        session.execute.return_value.fetchall.return_value = [
            SimpleNamespace(dag_id="bietlejuice.a", first_emit=first_emit)
        ]
        assert _fetch_sla_emitted(
            session, datetime(2026, 7, 24, 23, 55, tzinfo=timezone.utc)
        ) == {"bietlejuice.a": first_emit}


class TestCollectSlaFindingsDatasetWiring:
    def test_passes_live_graph_emissions_and_a_late_set_scoped_fetcher(self):
        live_upstream = {"bietlejuice.enrich_chatbot": {"bietlejuice.clean_chatbot"}}
        session = mock.Mock()
        with (
            mock.patch(
                f"{_MODULE}._load_upstream_index_safe", return_value={}
            ) as load_upstream,
            mock.patch(f"{_MODULE}._fetch_sla_history", return_value=[]),
            mock.patch(
                f"{_MODULE}._evaluate_sla_missing_runs", return_value=[]
            ) as evaluate,
            mock.patch(
                f"{_MODULE}._fetch_dataset_satisfaction", return_value={}
            ) as satisfaction,
        ):
            _collect_sla_findings(
                session,
                _SLA_CONFIG,
                datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc),
                {},
                candidates=["bietlejuice.enrich_chatbot"],
                dataset_upstream_index=live_upstream,
                emitted={"bietlejuice.clean_chatbot": datetime.now(timezone.utc)},
            )
            # The fetcher is deferred: only the late set knows which DAGs to ask about.
            satisfaction.assert_not_called()
            evaluate.call_args.kwargs["fetch_dataset_status"](
                ["bietlejuice.enrich_chatbot"]
            )
            satisfaction.assert_called_once_with(
                session, ["bietlejuice.enrich_chatbot"]
            )
        load_upstream.assert_called_once_with(live_upstream)
        assert evaluate.call_args.kwargs["emitted_this_cycle"] == {
            "bietlejuice.clean_chatbot"
        }

    def test_no_satisfaction_query_when_nothing_is_late(self):
        # _evaluate_sla_missing_runs returns before calling the fetcher at all.
        with (
            mock.patch(f"{_MODULE}._load_upstream_index_safe", return_value={}),
            mock.patch(f"{_MODULE}._fetch_sla_history", return_value=[]),
            mock.patch(f"{_MODULE}._fetch_dataset_satisfaction") as satisfaction,
        ):
            _collect_sla_findings(
                mock.Mock(),
                _SLA_CONFIG,
                datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc),
                {},
                candidates=["bietlejuice.enrich_chatbot"],
            )
        satisfaction.assert_not_called()


# --------------------------------------------------------------------------- #
# Required-dataset accounting (the reprocessing OR-branch is not a requirement)
# --------------------------------------------------------------------------- #
_FROD = ":first-run-of-day"
_REPRO = ":reprocessing"


def _uri(dag_id, task="load-x", reprocessing=False):
    """A dataset URI exactly as BietlejuiceDatasetService names it.

    4373 of the 4450 dependencies declared in ``dependencies.yaml`` carry the
    ``:first-run-of-day`` variant, and the reprocessing twin appends its own variant to
    whatever the dependency already was — so the common twin has four segments, not
    three.
    """
    return f"{dag_id}:{task}{_FROD}{_REPRO if reprocessing else ''}"


class TestProducerFromUri:
    @pytest.mark.parametrize(
        "uri,expected",
        [
            # Everything after the first separator is opaque: task, task plus variant,
            # and either of those with the reprocessing variant appended.
            ("bietlejuice.dw_a:load-dw-a-fact", "bietlejuice.dw_a"),
            ("bietlejuice.dw_a:load-dw-a-fact:first-run-of-day", "bietlejuice.dw_a"),
            (
                "bietlejuice.dw_a:load-dw-a-fact:first-run-of-day:reprocessing",
                "bietlejuice.dw_a",
            ),
            ("quintoml.wonka.seg:load-x:reprocessing", "quintoml.wonka.seg"),
            # Not a Bietlejuice URI: never guess a producer.
            ("s3://bucket/key", None),
            ("uri-a", None),
            ("a:", None),
            (":b", None),
        ],
    )
    def test_parses_the_dag_id_prefix_whatever_the_variant(self, uri, expected):
        assert _producer_from_uri(uri) == expected


class TestRequiredDatasets:
    def test_drops_the_reprocessing_branch(self):
        datasets = {
            _uri("bietlejuice.p1"): {"satisfied": True, "producers": set()},
            _uri("bietlejuice.p1", reprocessing=True): {
                "satisfied": False,
                "producers": set(),
            },
        }
        assert list(_required_datasets(datasets)) == [_uri("bietlejuice.p1")]

    def test_empty_and_none_are_empty(self):
        assert _required_datasets(None) == {}
        assert _required_datasets({}) == {}

    def test_a_task_named_reprocessing_is_still_required(self):
        # "<dag_id>:reprocessing" is a required dataset from a task that happens to be
        # called reprocessing, not the twin of another one.
        datasets = {
            "bietlejuice.p1:reprocessing": {"satisfied": True, "producers": set()}
        }
        assert _required_datasets(datasets) == datasets

    @pytest.mark.parametrize(
        "uri,is_twin",
        [
            # The dependency may already carry a variant, so the twin has four segments.
            ("bietlejuice.p1:load-x:first-run-of-day:reprocessing", True),
            ("bietlejuice.p1:load-x:reprocessing", True),
            ("bietlejuice.p1:load-x:first-run-of-day", False),
            ("bietlejuice.p1:load-x", False),
            ("bietlejuice.p1:reprocessing", False),
        ],
    )
    def test_twin_detection_covers_every_declared_dependency_shape(self, uri, is_twin):
        datasets = {uri: {"satisfied": False, "producers": set()}}
        assert (_required_datasets(datasets) == {}) is is_twin

    def test_reprocessing_only_schedule_collapses_to_empty(self):
        datasets = {
            _uri("bietlejuice.p1", reprocessing=True): {
                "satisfied": False,
                "producers": set(),
            }
        }
        assert _required_datasets(datasets) == {}


class TestQuotientExcludesReprocessing:
    def test_dw_accounts_receivable_reads_three_of_four_not_three_of_seven(self):
        # The 2026-07-25 shape: four real upstreams, three reprocessing twins, and a
        # single genuine blocker whose producer was still computing it.
        blocker = _uri("bietlejuice.dw_collection_recovery_quintoandar", "load-fopt")
        datasets = {
            _uri("bietlejuice.dw_listing"): {"satisfied": True, "producers": set()},
            _uri("bietlejuice.dw_region"): {"satisfied": True, "producers": set()},
            _uri("bietlejuice.enrich_retsuko"): {"satisfied": True, "producers": set()},
            blocker: {"satisfied": False, "producers": set()},
            _uri("bietlejuice.dw_listing", reprocessing=True): {
                "satisfied": False,
                "producers": set(),
            },
            _uri("bietlejuice.dw_region", reprocessing=True): {
                "satisfied": False,
                "producers": set(),
            },
            _uri(
                "bietlejuice.dw_collection_recovery_quintoandar",
                "load-fopt",
                reprocessing=True,
            ): {"satisfied": False, "producers": set()},
        }
        result = _classify_dataset_state(
            datasets, emitted_uris=set(), completed_dags=set()
        )
        assert result["dataset_required"] == 4
        assert result["dataset_satisfied"] == 3
        assert result["dataset_missing"] == [blocker]


def _blocked(datasets, *, emitted_uris=None, completed_dags=None):
    return _dataset_blocked(
        datasets,
        emitted_uris=emitted_uris,
        completed_dags=completed_dags or set(),
    )


class TestDatasetBlocked:
    def test_none_when_there_is_nothing_to_judge(self):
        assert _blocked(None) is None
        assert _blocked({}) is None
        # Reprocessing-only leaves no requirement, so still no opinion.
        assert (
            _blocked(
                {
                    _uri("bietlejuice.p1", reprocessing=True): {
                        "satisfied": False,
                        "producers": set(),
                    }
                }
            )
            is None
        )

    def test_not_blocked_when_every_required_dataset_is_satisfied(self):
        satisfied = {_uri("bietlejuice.p1"): {"satisfied": True, "producers": set()}}
        assert _blocked(satisfied) is False

    def test_blocked_while_the_upstream_is_still_working(self):
        uri = _uri("bietlejuice.p2")
        datasets = {
            _uri("bietlejuice.p1"): {"satisfied": True, "producers": set()},
            uri: {"satisfied": False, "producers": {"bietlejuice.p2"}},
        }
        assert _blocked(datasets) is True

    def test_not_blocked_when_the_missing_dataset_already_fired(self):
        """The dropped-event signature: the event exists, the queue row does not."""
        uri = _uri("bietlejuice.p2")
        datasets = {
            _uri("bietlejuice.p1"): {"satisfied": True, "producers": set()},
            uri: {"satisfied": False, "producers": {"bietlejuice.p2"}},
        }
        assert _blocked(datasets, emitted_uris={uri}) is False

    def test_not_blocked_when_the_producer_finished_without_delivering(self):
        datasets = {
            _uri("bietlejuice.p2"): {
                "satisfied": False,
                "producers": {"bietlejuice.p2"},
            }
        }
        assert (
            _blocked(datasets, emitted_uris=set(), completed_dags={"bietlejuice.p2"})
            is False
        )

    def test_a_mid_flight_producer_that_emitted_another_outlet_still_blocks(self):
        """The 2026-07-25 avalanche: emitting one outlet is not finishing the run."""
        waiting_on = _uri("bietlejuice.p2", "load-fact")
        datasets = {waiting_on: {"satisfied": False, "producers": {"bietlejuice.p2"}}}
        assert (
            _blocked(
                datasets,
                emitted_uris={_uri("bietlejuice.p2", "load-dim")},
                completed_dags=set(),
            )
            is True
        )

    def test_unreadable_event_table_falls_back_to_run_completion(self):
        uri = _uri("bietlejuice.p2")
        datasets = {uri: {"satisfied": False, "producers": {"bietlejuice.p2"}}}
        assert _blocked(datasets, emitted_uris=None) is True
        assert (
            _blocked(datasets, emitted_uris=None, completed_dags={"bietlejuice.p2"})
            is False
        )

    def test_unsatisfied_reprocessing_twin_does_not_block(self):
        datasets = {
            _uri("bietlejuice.p1"): {"satisfied": True, "producers": set()},
            _uri("bietlejuice.p1", reprocessing=True): {
                "satisfied": False,
                "producers": set(),
            },
        }
        assert _blocked(datasets) is False


class TestProducerRecoveredWithoutTaskOutletRows:
    def test_status_attributes_producer_from_uri_when_join_is_empty(self):
        uri = _uri("bietlejuice.dw_collection_recovery_quintoandar", "load-fact")
        status = _build_dataset_status(
            [_dataset_row("bietlejuice.dw_ar", uri, 0, None)]
        )
        assert status["bietlejuice.dw_ar"][uri]["producers"] == {
            "bietlejuice.dw_collection_recovery_quintoandar"
        }

    def test_status_unions_both_producer_sources(self):
        uri = _uri("bietlejuice.p1")
        status = _build_dataset_status(
            [_dataset_row("bietlejuice.d", uri, 0, "bietlejuice.p_declared")]
        )
        assert status["bietlejuice.d"][uri]["producers"] == {
            "bietlejuice.p1",
            "bietlejuice.p_declared",
        }

    def test_status_never_lists_the_consumer_as_its_own_producer(self):
        uri = _uri("bietlejuice.d")
        status = _build_dataset_status([_dataset_row("bietlejuice.d", uri, 0, None)])
        assert status["bietlejuice.d"][uri]["producers"] == set()

    def test_graph_builds_edges_from_uri_when_join_is_empty(self):
        # An INNER JOIN on task_outlet_dataset_reference returned nothing at all, which
        # left the live graph inert and every quintoml.* DAG looking like its own root.
        upstream, downstream = _build_dataset_indexes(
            [
                _edge_row(
                    "quintoml.wonka.segmentation",
                    None,
                    uri=_uri("bietlejuice.dw_collections_segmentation"),
                )
            ]
        )
        assert upstream == {
            "quintoml.wonka.segmentation": {"bietlejuice.dw_collections_segmentation"}
        }
        assert downstream == {
            "bietlejuice.dw_collections_segmentation": {"quintoml.wonka.segmentation"}
        }

    def test_graph_unions_both_producer_sources_and_skips_self_edges(self):
        upstream, _ = _build_dataset_indexes(
            [
                _edge_row(
                    "bietlejuice.d",
                    "bietlejuice.p_declared",
                    uri=_uri("bietlejuice.p_uri"),
                ),
                _edge_row("bietlejuice.d", None, uri=_uri("bietlejuice.d")),
            ]
        )
        assert upstream == {
            "bietlejuice.d": {"bietlejuice.p_declared", "bietlejuice.p_uri"}
        }


# --------------------------------------------------------------------------- #
# Readiness-gated root selection (the 2026-07-25 avalanche)
# --------------------------------------------------------------------------- #
class TestReadinessGatedRoots:
    _UPSTREAM = {
        "bietlejuice.dw_accounts_receivable": {
            "bietlejuice.dw_collection_recovery_quintoandar"
        },
        "bietlejuice.dw_collections_segmentation": {
            "bietlejuice.dw_collection_recovery_quintoandar"
        },
    }

    def _status(self, satisfied):
        return {
            dag_id: {
                _uri("bietlejuice.dw_collection_recovery_quintoandar"): {
                    "satisfied": satisfied,
                    "producers": {"bietlejuice.dw_collection_recovery_quintoandar"},
                }
            }
            for dag_id in self._UPSTREAM
        }

    def test_mid_flight_upstream_no_longer_promotes_its_dependents(self):
        # The upstream emitted one early outlet, so it counts as succeeded and has left
        # the late set — but the dataset each dependent needs is still being computed.
        late = set(self._UPSTREAM)
        roots, suppressed, used_fallback = _select_sla_roots(
            late,
            upstream_index=self._UPSTREAM,
            succeeded_this_cycle={"bietlejuice.dw_collection_recovery_quintoandar"},
            dataset_status=self._status(False),
        )
        assert roots == []
        assert suppressed == 2
        assert used_fallback is False

    def test_ready_and_still_not_started_is_the_root_we_want(self):
        late = set(self._UPSTREAM)
        roots, _, used_fallback = _select_sla_roots(
            late,
            upstream_index=self._UPSTREAM,
            succeeded_this_cycle={"bietlejuice.dw_collection_recovery_quintoandar"},
            dataset_status=self._status(True),
        )
        assert roots == sorted(self._UPSTREAM)
        assert used_fallback is False

    def test_unreadable_status_keeps_the_previous_behaviour(self):
        late = set(self._UPSTREAM)
        roots, _, _ = _select_sla_roots(
            late,
            upstream_index=self._UPSTREAM,
            succeeded_this_cycle={"bietlejuice.dw_collection_recovery_quintoandar"},
            dataset_status=None,
        )
        assert roots == sorted(self._UPSTREAM)

    def test_cron_dag_without_datasets_is_unaffected(self):
        roots, _, _ = _select_sla_roots(
            {"bietlejuice.cron_dag"},
            upstream_index={},
            succeeded_this_cycle=set(),
            dataset_status={"bietlejuice.cron_dag": {}},
        )
        assert roots == ["bietlejuice.cron_dag"]

    def test_fallback_stays_silent_on_a_dag_known_to_be_unready(self):
        # Nothing is confirmed (the upstream never succeeded), so the old code fell back
        # to the tops of the late set. Positive evidence of blockage outranks that.
        late = {"bietlejuice.dw_accounts_receivable"}
        roots, suppressed, used_fallback = _select_sla_roots(
            late,
            upstream_index=self._UPSTREAM,
            succeeded_this_cycle=set(),
            expected_this_cycle=late
            | {"bietlejuice.dw_collection_recovery_quintoandar"},
            dataset_status=self._status(False),
        )
        assert roots == []
        assert suppressed == 1
        assert used_fallback is False

    def test_fallback_still_fires_when_status_is_unavailable(self):
        late = {"bietlejuice.dw_accounts_receivable"}
        roots, _, used_fallback = _select_sla_roots(
            late,
            upstream_index=self._UPSTREAM,
            succeeded_this_cycle=set(),
            expected_this_cycle=late
            | {"bietlejuice.dw_collection_recovery_quintoandar"},
            dataset_status=None,
        )
        assert roots == ["bietlejuice.dw_accounts_receivable"]
        assert used_fallback is True

    def test_a_dropped_event_is_reported_not_suppressed(self):
        """Prod 2026-07-26: every tick reported 0 roots while dozens stayed late.

        Gating on "all datasets satisfied" also hid the DAGs stuck at N-1/N whose
        producer had already delivered, which is the failure the guard exists for.
        """
        late = set(self._UPSTREAM)
        roots, suppressed, _ = _select_sla_roots(
            late,
            upstream_index=self._UPSTREAM,
            succeeded_this_cycle={"bietlejuice.dw_collection_recovery_quintoandar"},
            dataset_status=self._status(False),
            emitted_uris={_uri("bietlejuice.dw_collection_recovery_quintoandar")},
        )
        assert roots == sorted(self._UPSTREAM)
        assert suppressed == 0

    def test_a_producer_that_finished_without_delivering_is_reported(self):
        late = set(self._UPSTREAM)
        roots, _, _ = _select_sla_roots(
            late,
            upstream_index=self._UPSTREAM,
            succeeded_this_cycle={"bietlejuice.dw_collection_recovery_quintoandar"},
            dataset_status=self._status(False),
            emitted_uris=set(),
            completed_dags={"bietlejuice.dw_collection_recovery_quintoandar"},
        )
        assert roots == sorted(self._UPSTREAM)


class TestMissingRunAlertCap:
    def _findings(self, count):
        return [
            {"dag_id": f"bietlejuice.dag_{i:02d}", "late_by_s": float(i * 60)}
            for i in range(count)
        ]

    def test_under_the_cap_is_untouched(self):
        findings = self._findings(3)
        assert _apply_missing_run_cap(findings, {"sla_max_missing_run_alerts": 5}) == (
            findings
        )
        assert all("capped_count" not in f for f in findings)

    def test_keeps_the_latest_roots_and_records_what_was_withheld(self):
        kept = _apply_missing_run_cap(
            self._findings(10), {"sla_max_missing_run_alerts": 3}
        )
        assert [f["dag_id"] for f in kept] == [
            "bietlejuice.dag_09",
            "bietlejuice.dag_08",
            "bietlejuice.dag_07",
        ]
        assert all(f["capped_count"] == 7 for f in kept)

    def test_zero_or_missing_cap_disables_it(self):
        findings = self._findings(4)
        assert _apply_missing_run_cap(findings, {"sla_max_missing_run_alerts": 0}) == (
            findings
        )
        assert _apply_missing_run_cap(findings, {}) == findings

    def test_cap_survives_into_the_delivered_entry(self):
        # Chat text is built from the ledger entry, not the finding, so a field that
        # stops at _entry_from_finding never reaches an operator.
        entry = _entry_from_finding(
            {
                "kind": _KIND_MISSING_RUN,
                "dag_id": "bietlejuice.dw_accounts_receivable",
                "run_id": "sla::2026-07-24T23:55:00+00:00",
                "due_at": "2026-07-25T14:00:00+00:00",
                "expected_start": "2026-07-25T13:00:00+00:00",
                "grace_minutes": 60,
                "percentile": 90,
                "history_count": 14,
                "lookback_days": 14,
                "capped_count": 7,
            }
        )
        assert entry["capped_count"] == 7
        assert "• Alert cap reached" not in _build_alert_text(entry)

    def test_message_omits_the_cap_from_chat(self):
        text = _missing_run_initial_text(
            {
                "kind": _KIND_MISSING_RUN,
                "dag_id": "bietlejuice.dw_accounts_receivable",
                "run_id": "sla::2026-07-24T23:55:00+00:00",
                "due_at": "2026-07-25T14:00:00+00:00",
                "expected_start": "2026-07-25T13:00:00+00:00",
                "grace_minutes": 60,
                "percentile": 90,
                "history_count": 14,
                "lookback_days": 14,
                "capped_count": 7,
            },
            3600,
        )
        assert "• Alert cap reached" not in text


class TestTwentyThreeHundredTickRegression:
    """End-to-end replay of the 2026-07-25 23:00 tick that produced the avalanche.

    dw_collection_recovery_quintoandar was triggered by hand and emitted its first
    outlet at 22:58, which marked it succeeded and pulled it out of the late set. Its
    two dependents were still short the dataset it had not finished computing, yet both
    were promoted to confirmed roots and alerted; both then started on their own within
    fifteen minutes with no human action.
    """

    _ROOT = "bietlejuice.dw_collection_recovery_quintoandar"
    _DEPENDENTS = [
        "bietlejuice.dw_accounts_receivable",
        "bietlejuice.dw_collections_segmentation",
    ]

    def _history(self, now):
        cycle = _cycle_anchor(now, hhmm="20:55")
        rows = []
        for i in range(12):
            anchor = cycle - timedelta(days=i + 1)
            for dag_id in self._DEPENDENTS:
                rows.append(
                    SimpleNamespace(
                        dag_id=dag_id,
                        start_date=anchor + timedelta(minutes=230.0),
                        state="success",
                    )
                )
        return rows

    def _status(self, satisfied):
        return {
            dag_id: {
                _uri(self._ROOT, "load-fact"): {
                    "satisfied": satisfied,
                    "producers": {self._ROOT},
                },
                _uri(self._ROOT, "load-fact", reprocessing=True): {
                    "satisfied": False,
                    "producers": {self._ROOT},
                },
            }
            for dag_id in self._DEPENDENTS
        }

    def _run(self, satisfied):
        now = datetime(2026, 7, 25, 12, 0, tzinfo=timezone.utc)
        return _evaluate_sla_missing_runs(
            list(self._DEPENDENTS),
            self._history(now),
            now=now,
            config=_SLA_CONFIG,
            upstream_index={d: {self._ROOT} for d in self._DEPENDENTS},
            downstream_index={},
            expected_dag_ids=set(self._DEPENDENTS) | {self._ROOT},
            # The mid-flight upstream emitted one outlet, so it counts as succeeded.
            emitted_this_cycle={self._ROOT},
            fetch_dataset_status=lambda dag_ids: self._status(satisfied),
        )

    def test_mid_flight_upstream_produces_no_alerts(self):
        assert self._run(satisfied=False) == []

    def test_same_tick_still_alerts_once_the_dataset_lands(self):
        # The gate must not simply mute dataset-scheduled DAGs: a genuinely dropped
        # event leaves them satisfied and still not running, which is the real alert.
        findings = self._run(satisfied=True)
        assert sorted(f["dag_id"] for f in findings) == self._DEPENDENTS
        assert all(f["dataset_verdict"] == _VERDICT_DROPPED_EVENT for f in findings)
        # The reprocessing twin is neither required nor counted as missing.
        assert all(f["dataset_required"] == 1 for f in findings)
        assert all(f["dataset_missing"] == [] for f in findings)


class _FrozenDatetime(datetime):
    """``datetime`` whose ``now()`` is pinned, for end-to-end monitor calls.

    ``monitor_dag_runtimes`` reads the wall clock once (``datetime.now(timezone.utc)``)
    and derives both ``now`` and the cycle anchor from it, so an unpinned clock makes
    deadline assertions depend on the time of day the suite happens to run.
    """

    @classmethod
    def now(cls, tz=None):
        return _FROZEN_NOW if tz is None else _FROZEN_NOW.astimezone(tz)


class TestMonitorPagesDeadlineMiss:
    """Covers the wiring the deadline_miss unit tests cannot reach."""

    def test_declared_deadline_miss_pages_jira_end_to_end(self):
        with (
            mock.patch(f"{_MODULE}.datetime", _FrozenDatetime),
            mock.patch(f"{_MODULE}.ConfigurationService") as mock_cfg,
            mock.patch(f"{_MODULE}.Variable") as mock_var,
            mock.patch(f"{_MODULE}._load_downstream_index_safe", return_value={}),
            mock.patch(f"{_MODULE}._fetch_running_runs", return_value=[]),
            mock.patch(f"{_MODULE}._collect_sla_findings", return_value=[]),
            mock.patch(
                f"{_MODULE}._fetch_sla_candidates", return_value=[_CRITICAL_DAG]
            ),
            mock.patch(f"{_MODULE}._fetch_sla_history", return_value=[]),
            mock.patch(f"{_MODULE}._fetch_sla_emitted", return_value={}),
            mock.patch(f"{_MODULE}._fetch_run_states", return_value={}),
            mock.patch(f"{_MODULE}._post_gchat", return_value=True) as mock_post,
            mock.patch(f"{_MODULE}._send_jira_alert", return_value=True) as mock_jira,
            mock.patch(
                f"{_MODULE}._fetch_declared_criticality",
                return_value=({_CRITICAL_DAG: "Critical"}, {_CRITICAL_DAG: "10:00"}),
            ),
        ):
            mock_cfg.return_value.get_config.side_effect = _config_get
            mock_var.get.side_effect = _variable_get_factory(environment="prod")
            monitor_dag_runtimes(session=_db_session(), run_conf={})

        mock_jira.assert_called_once()
        finding = mock_jira.call_args.args[0]
        assert finding["kind"] == _KIND_DEADLINE_MISS
        assert finding["dag_id"] == _CRITICAL_DAG
        assert finding["tier"] == "critical"
        assert finding["deadline_localtime"] == "10:00"
        assert finding["late_by_s"] > 0
        assert finding["run_id"].startswith("deadline::")
        mock_post.assert_called_once()
