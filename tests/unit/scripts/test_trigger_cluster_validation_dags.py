import asyncio
import io
import sys
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import MagicMock, call, patch

import pytest
import requests

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT))

from scripts import cluster_validation_dag_discovery as discovery  # noqa: E402
from scripts import trigger_cluster_validation_dags as trigger_script  # noqa: E402
from scripts.airflow_rest_client import AirflowApiError  # noqa: E402

EXPECTED_CONF = {
    "run_type": "test_run",
    "load_start_date": "2024-01-01",
    "load_end_date": "2024-01-07",
}


def _sample_dag() -> discovery.ValidationDag:
    return discovery.ValidationDag(
        line="agents",
        dag_name="dw_agent",
        dag_id="bietlejuice.dw_agent__validation",
        cluster_path=Path("dags/agents/dw_agent/dw_agent_cluster.yml"),
    )


@pytest.fixture
def sample_dags_root(tmp_path: Path) -> Path:
    root = tmp_path / "dags"
    agents_dir = root / "agents" / "dw_agent"
    agents_dir.mkdir(parents=True)
    fintech_dir = root / "fintech" / "dw_credit"
    fintech_dir.mkdir(parents=True)
    platform_dir = root / "platform" / "skipped"
    platform_dir.mkdir(parents=True)

    (agents_dir / "dw_agent_cluster.yml").write_text(
        "cluster:\n  type: databricks_16_4_med_general_cluster\n"
        "validation:\n  cluster:\n    type: consolidation_s_general_cluster\n",
        encoding="utf-8",
    )
    (fintech_dir / "dw_credit_cluster.yml").write_text(
        "cluster:\n  type: databricks_16_4_med_general_cluster\n"
        "validation:\n  cluster:\n    type: consolidation_s_general_cluster\n",
        encoding="utf-8",
    )
    (platform_dir / "skipped_cluster.yml").write_text(
        "cluster:\n  type: databricks_16_4_med_general_cluster\n",
        encoding="utf-8",
    )
    return root


class TestDiscovery:
    def test_uses_declaration_dag_name_for_airflow_dag_id(self, tmp_path: Path) -> None:
        root = tmp_path / "dags"
        qube_dir = root / "qube" / "dimensions_offer_type"
        qube_dir.mkdir(parents=True)
        (qube_dir / "dimensions_offer_type_cluster.yml").write_text(
            "cluster:\n  type: databricks_16_4_med_general_cluster\n"
            "validation:\n  cluster:\n    type: consolidation_s_general_cluster\n",
            encoding="utf-8",
        )
        (qube_dir / "dimensions_offer_type_declaration.yml").write_text(
            "dag:\n  name: qube_dimension_offer_type\n",
            encoding="utf-8",
        )

        items = discovery.discover_validation_dags(root)

        assert len(items) == 1
        assert items[0].dag_name == "dimensions_offer_type"
        assert items[0].dag_id == "bietlejuice.qube_dimension_offer_type__validation"

    def test_discover_validation_dags(self, sample_dags_root: Path) -> None:
        items = discovery.discover_validation_dags(sample_dags_root)

        assert len(items) == 2
        assert {item.dag_name for item in items} == {"dw_agent", "dw_credit"}
        assert all(item.dag_id.endswith("__validation") for item in items)
        assert all(item.dag_id.startswith("bietlejuice.") for item in items)

    def test_filter_by_line(self, sample_dags_root: Path) -> None:
        items = discovery.discover_validation_dags(sample_dags_root)
        filtered = discovery.filter_validation_dags(items, lines="agents")

        assert len(filtered) == 1
        assert filtered[0].line == "agents"

    def test_filter_by_dag_name(self, sample_dags_root: Path) -> None:
        items = discovery.discover_validation_dags(sample_dags_root)
        filtered = discovery.filter_validation_dags(items, dag_names="dw_credit")

        assert len(filtered) == 1
        assert filtered[0].dag_name == "dw_credit"

    def test_filter_lines_or_dags(self, sample_dags_root: Path) -> None:
        items = discovery.discover_validation_dags(sample_dags_root)
        filtered = discovery.filter_validation_dags(
            items,
            lines="agents",
            dag_names="dw_credit",
        )

        assert len(filtered) == 2

    def test_exclude_line(self, sample_dags_root: Path) -> None:
        items = discovery.discover_validation_dags(sample_dags_root)
        filtered = discovery.filter_validation_dags(items, exclude_lines="fintech")

        assert len(filtered) == 1
        assert filtered[0].line == "agents"

    def test_filter_by_dag_id(self, sample_dags_root: Path) -> None:
        items = discovery.discover_validation_dags(sample_dags_root)
        filtered = discovery.filter_validation_dags(
            items,
            dag_ids="bietlejuice.dw_agent__validation",
        )

        assert len(filtered) == 1
        assert filtered[0].dag_name == "dw_agent"

    def test_original_dag_id(self) -> None:
        dag = discovery.ValidationDag(
            line="agents",
            dag_name="dw_agent",
            dag_id="bietlejuice.dw_agent__validation",
            cluster_path=Path("dags/agents/dw_agent/dw_agent_cluster.yml"),
        )
        assert dag.original_dag_id == "bietlejuice.dw_agent"


class TestTriggerConf:
    def test_requires_dates_by_default(self) -> None:
        args = trigger_script._parse_args([])

        with pytest.raises(SystemExit):
            trigger_script._resolve_trigger_conf(args)

    def test_allow_default_dates(self) -> None:
        args = trigger_script._parse_args(["--allow-default-dates"])
        conf = trigger_script._resolve_trigger_conf(args)

        assert conf["run_type"] == "test_run"
        assert conf["load_start_date"] == "2019-01-01"
        assert conf["load_end_date"] == "2026-12-31"

    def test_from_prod_run_rejects_explicit_dates(self) -> None:
        with pytest.raises(SystemExit):
            trigger_script._parse_args(
                [
                    "--from-prod-run",
                    "--load-start-date",
                    "2024-01-01",
                    "--load-end-date",
                    "2024-01-07",
                ]
            )

    def test_list_mode_does_not_require_dates(self) -> None:
        args = trigger_script._parse_args(["--list"])
        assert not trigger_script._needs_explicit_load_dates(args)


class TestPollDelay:
    def test_zero_base_interval(self) -> None:
        assert (
            trigger_script._compute_poll_delay(
                0,
                base_interval=0,
                max_interval=300,
                jitter_fraction=0.25,
            )
            == 0.0
        )
        assert (
            trigger_script._compute_initial_poll_delay(
                base_interval=0,
                max_interval=300,
                jitter_fraction=0.25,
            )
            == 0.0
        )

    def test_exponential_backoff_without_jitter(self) -> None:
        assert (
            trigger_script._compute_poll_delay(
                0,
                base_interval=30,
                max_interval=300,
                jitter_fraction=0,
            )
            == 30.0
        )
        assert (
            trigger_script._compute_poll_delay(
                3,
                base_interval=30,
                max_interval=300,
                jitter_fraction=0,
            )
            == 240.0
        )
        assert (
            trigger_script._compute_poll_delay(
                10,
                base_interval=30,
                max_interval=300,
                jitter_fraction=0,
            )
            == 300.0
        )

    def test_jitter_multiplier(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(
            trigger_script.random,
            "uniform",
            lambda _low, _high: 1.25,
        )
        assert (
            trigger_script._compute_poll_delay(
                0,
                base_interval=30,
                max_interval=300,
                jitter_fraction=0.25,
            )
            == 37.5
        )

    def test_initial_stagger_uses_uniform_up_to_attempt_zero(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(
            trigger_script,
            "_compute_poll_delay",
            lambda *_args, **_kwargs: 30.0,
        )
        monkeypatch.setattr(
            trigger_script.random,
            "uniform",
            lambda _low, high: 0.5 * high,
        )
        assert (
            trigger_script._compute_initial_poll_delay(
                base_interval=30,
                max_interval=300,
                jitter_fraction=0.25,
            )
            == 15.0
        )

    def test_initial_stagger_bounds(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(
            trigger_script,
            "_compute_poll_delay",
            lambda *_args, **_kwargs: 30.0,
        )

        monkeypatch.setattr(
            trigger_script.random,
            "uniform",
            lambda _low, _high: 0.0,
        )
        assert (
            trigger_script._compute_initial_poll_delay(
                base_interval=30,
                max_interval=300,
                jitter_fraction=0.25,
            )
            == 0.0
        )

        monkeypatch.setattr(
            trigger_script.random,
            "uniform",
            lambda _low, high: high,
        )
        assert (
            trigger_script._compute_initial_poll_delay(
                base_interval=30,
                max_interval=300,
                jitter_fraction=0.25,
            )
            == 30.0
        )


class TestConfMatches:
    def test_matches_expected_keys(self) -> None:
        assert trigger_script._conf_matches(EXPECTED_CONF, EXPECTED_CONF)

    def test_rejects_mismatched_load_window(self) -> None:
        other = {**EXPECTED_CONF, "load_end_date": "2024-02-01"}
        assert not trigger_script._conf_matches(other, EXPECTED_CONF)


class TestResolveRunAction:
    def test_active_run_returns_monitor(self) -> None:
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "run__active",
                "state": "running",
                "start_date": "2024-01-02T00:00:00Z",
                "conf": EXPECTED_CONF,
            }
        ]
        action = trigger_script._resolve_run_action(
            client,
            _sample_dag(),
            force_retrigger=False,
            dag_runs_lookback=25,
        )
        assert action.action == "monitor"
        assert action.dag_run_id == "run__active"

    def test_last_success_returns_skip(self) -> None:
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "run__ok",
                "state": "success",
                "start_date": "2024-01-02T00:00:00Z",
                "conf": EXPECTED_CONF,
            }
        ]
        action = trigger_script._resolve_run_action(
            client,
            _sample_dag(),
            force_retrigger=False,
            dag_runs_lookback=25,
        )
        assert action.action == "skip"
        assert action.dag_run_id == "run__ok"
        assert "last run success: run__ok" in action.reason

    def test_success_with_empty_conf_returns_skip(self) -> None:
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "manual__2026-06-03",
                "state": "success",
                "start_date": "2026-06-03T04:00:00Z",
                "conf": {},
            }
        ]
        action = trigger_script._resolve_run_action(
            client,
            _sample_dag(),
            force_retrigger=False,
            dag_runs_lookback=25,
        )
        assert action.action == "skip"
        assert action.dag_run_id == "manual__2026-06-03"

    def test_success_with_ui_default_conf_returns_skip(self) -> None:
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "manual__ui",
                "state": "success",
                "start_date": "2026-06-03T04:00:00Z",
                "conf": {
                    "run_type": "default",
                    "load_start_date": None,
                    "load_end_date": None,
                },
            }
        ]
        action = trigger_script._resolve_run_action(
            client,
            _sample_dag(),
            force_retrigger=False,
            dag_runs_lookback=25,
        )
        assert action.action == "skip"

    def test_failed_only_returns_trigger(self) -> None:
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "run__bad",
                "state": "failed",
                "start_date": "2024-01-02T00:00:00Z",
                "conf": EXPECTED_CONF,
            }
        ]
        action = trigger_script._resolve_run_action(
            client,
            _sample_dag(),
            force_retrigger=False,
            dag_runs_lookback=25,
        )
        assert action.action == "trigger"

    def test_conf_mismatch_still_skips_on_last_success(self) -> None:
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "run__other",
                "state": "success",
                "start_date": "2024-01-02T00:00:00Z",
                "conf": {**EXPECTED_CONF, "load_start_date": "2020-01-01"},
            }
        ]
        action = trigger_script._resolve_run_action(
            client,
            _sample_dag(),
            force_retrigger=False,
            dag_runs_lookback=25,
        )
        assert action.action == "skip"

    def test_failed_latest_with_older_success_returns_trigger(self) -> None:
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "run__ok",
                "state": "success",
                "start_date": "2024-01-01T00:00:00Z",
                "conf": EXPECTED_CONF,
            },
            {
                "dag_run_id": "run__bad",
                "state": "failed",
                "start_date": "2024-01-02T00:00:00Z",
                "conf": EXPECTED_CONF,
            },
        ]
        action = trigger_script._resolve_run_action(
            client,
            _sample_dag(),
            force_retrigger=False,
            dag_runs_lookback=25,
        )
        assert action.action == "trigger"

    def test_active_run_beats_skip(self) -> None:
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "run__ok",
                "state": "success",
                "start_date": "2024-01-01T00:00:00Z",
                "conf": EXPECTED_CONF,
            },
            {
                "dag_run_id": "run__active",
                "state": "running",
                "start_date": "2024-01-02T00:00:00Z",
                "conf": {},
            },
        ]
        action = trigger_script._resolve_run_action(
            client,
            _sample_dag(),
            force_retrigger=False,
            dag_runs_lookback=25,
        )
        assert action.action == "monitor"
        assert action.dag_run_id == "run__active"

    def test_recent_success_within_cooldown_skips_even_with_force_retrigger(
        self,
    ) -> None:
        now = datetime(2026, 6, 11, 16, 0, 0, tzinfo=timezone.utc)
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "run__recent_ok",
                "state": "success",
                "start_date": "2026-06-11T14:30:00+00:00",
                "end_date": "2026-06-11T15:30:00+00:00",
                "conf": EXPECTED_CONF,
            }
        ]
        action = trigger_script._resolve_run_action(
            client,
            _sample_dag(),
            force_retrigger=True,
            dag_runs_lookback=25,
            validation_cooldown_hours=2,
            now=now,
        )
        assert action.action == "skip"
        assert "recent success run within 2h" in action.reason

    def test_old_success_triggers_with_force_retrigger(self) -> None:
        now = datetime(2026, 6, 11, 16, 0, 0, tzinfo=timezone.utc)
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "run__old_ok",
                "state": "success",
                "start_date": "2026-06-11T10:00:00+00:00",
                "end_date": "2026-06-11T11:00:00+00:00",
                "conf": EXPECTED_CONF,
            }
        ]
        action = trigger_script._resolve_run_action(
            client,
            _sample_dag(),
            force_retrigger=True,
            dag_runs_lookback=25,
            validation_cooldown_hours=2,
            now=now,
        )
        assert action.action == "trigger"
        assert action.reason == "force-retrigger"

    def test_recent_failed_within_cooldown_skips(self) -> None:
        now = datetime(2026, 6, 11, 16, 0, 0, tzinfo=timezone.utc)
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "run__recent_bad",
                "state": "failed",
                "start_date": "2026-06-11T15:00:00+00:00",
                "end_date": "2026-06-11T15:30:00+00:00",
                "conf": EXPECTED_CONF,
            }
        ]
        action = trigger_script._resolve_run_action(
            client,
            _sample_dag(),
            force_retrigger=False,
            dag_runs_lookback=25,
            validation_cooldown_hours=2,
            now=now,
        )
        assert action.action == "skip"
        assert "recent failed run within 2h" in action.reason

    def test_active_run_without_conf_match_still_monitors(self) -> None:
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "run__active",
                "state": "running",
                "start_date": "2024-01-02T00:00:00Z",
                "conf": {},
            }
        ]
        action = trigger_script._resolve_run_action(
            client,
            _sample_dag(),
            force_retrigger=False,
            dag_runs_lookback=25,
        )
        assert action.action == "monitor"
        assert action.dag_run_id == "run__active"


def _validation_dag_with_id(dag_id: str) -> discovery.ValidationDag:
    return discovery.ValidationDag(
        line="support_and_service",
        dag_name="test",
        dag_id=dag_id,
        cluster_path=Path("dags/support_and_service/test/test_cluster.yml"),
    )


def _dag_id_with_length(total_length: int) -> str:
    prefix = "bietlejuice."
    suffix = "__validation"
    inner_len = total_length - len(prefix) - len(suffix)
    assert inner_len >= 0
    return f"{prefix}{'x' * inner_len}{suffix}"


class TestDatabricksDagIdLength:
    def test_braze_length_dag_id_exceeds_limit(self) -> None:
        dag_id = "bietlejuice.enrich_braze_events_user_centric_periodicity__validation"
        assert len(dag_id) == 68
        assert trigger_script._dag_id_exceeds_databricks_limit(dag_id)

    def test_braze_length_skipped_in_build_plans(self) -> None:
        dag_id = "bietlejuice.enrich_braze_events_user_centric_periodicity__validation"
        client = MagicMock()
        args = trigger_script._parse_args(["--from-prod-run"])
        plans = trigger_script._build_execution_plans(
            client,
            [_validation_dag_with_id(dag_id)],
            args,
        )
        assert len(plans) == 1
        assert plans[0].conf is None
        assert "too long for Databricks" in (plans[0].skip_reason or "")
        client.list_dag_runs.assert_not_called()

    def test_force_retrigger_still_skips_too_long_dag_id(self) -> None:
        dag_id = (
            "bietlejuice.arquivo_confidencial_integration_report__validation"
        )
        client = MagicMock()
        action = trigger_script._resolve_run_action(
            client,
            _validation_dag_with_id(dag_id),
            force_retrigger=True,
            dag_runs_lookback=25,
        )
        assert action.action == "skip"
        assert "too long for Databricks" in action.reason
        client.list_dag_runs.assert_not_called()

    def test_force_retrigger_does_not_trigger_too_long_dag(self) -> None:
        dag_id = (
            "bietlejuice.arquivo_confidencial_integration_report__validation"
        )
        client = MagicMock()
        plan = trigger_script.DagExecutionPlan(
            dag=_validation_dag_with_id(dag_id),
            conf=EXPECTED_CONF,
            validation_action=trigger_script.RunAction(
                action="trigger",
                dag_run_id=None,
                reason="force-retrigger",
            ),
        )

        outcomes = asyncio.run(
            trigger_script.trigger_and_monitor(
                client,
                [plan],
                max_parallel=1,
                max_runs=1,
                force_retrigger=True,
                dag_runs_lookback=25,
                poll_interval=0,
                timeout=30,
                verbose=False,
                log_tail_lines=20,
            )
        )

        assert outcomes[0].final_state == "skipped"
        assert "too long for Databricks" in (outcomes[0].error_message or "")
        client.trigger_dag_run.assert_not_called()

    def test_arquivo_confidencial_length_skipped(self) -> None:
        dag_id = (
            "bietlejuice.arquivo_confidencial_integration_report__validation"
        )
        assert len(dag_id) == 63
        assert trigger_script._dag_id_exceeds_databricks_limit(dag_id)

        client = MagicMock()
        args = trigger_script._parse_args(["--from-prod-run"])
        plans = trigger_script._build_execution_plans(
            client,
            [_validation_dag_with_id(dag_id)],
            args,
        )
        assert plans[0].conf is None
        assert "too long for Databricks" in (plans[0].skip_reason or "")
        client.list_dag_runs.assert_not_called()

    def test_dag_id_at_limit_allowed(self) -> None:
        dag_id = _dag_id_with_length(56)
        assert len(dag_id) == 56
        assert not trigger_script._dag_id_exceeds_databricks_limit(dag_id)

        client = MagicMock()
        client.list_dag_runs.return_value = []
        args = trigger_script._parse_args(
            [
                "--load-start-date",
                "2024-01-01",
                "--load-end-date",
                "2024-01-07",
            ]
        )
        plans = trigger_script._build_execution_plans(
            client,
            [_validation_dag_with_id(dag_id)],
            args,
        )
        assert plans[0].skip_reason is None

    def test_dag_id_one_over_limit_skipped(self) -> None:
        dag_id = _dag_id_with_length(57)
        assert len(dag_id) == 57
        assert trigger_script._dag_id_exceeds_databricks_limit(dag_id)

        client = MagicMock()
        args = trigger_script._parse_args(["--from-prod-run"])
        plans = trigger_script._build_execution_plans(
            client,
            [_validation_dag_with_id(dag_id)],
            args,
        )
        assert plans[0].conf is None
        assert "limit 56" in (plans[0].skip_reason or "")


class TestTransientApiError:
    def test_request_exception_is_transient(self) -> None:
        assert trigger_script._is_transient_api_error(requests.ConnectionError())

    def test_retryable_status_codes(self) -> None:
        assert trigger_script._is_transient_api_error(
            AirflowApiError("rate limit", status_code=429)
        )
        assert not trigger_script._is_transient_api_error(
            AirflowApiError("not found", status_code=404)
        )


class TestMonitorRun:
    def test_monitor_success(self) -> None:
        client = MagicMock()
        client.get_dag_run.side_effect = [
            {"state": "running"},
            {"state": "success"},
        ]
        client.list_task_instances.return_value = []

        printer = trigger_script.EventPrinter(
            stdout=io.StringIO(),
            stderr=io.StringIO(),
        )
        progress = trigger_script.ProgressTracker(total=1)
        dag = discovery.ValidationDag(
            line="agents",
            dag_name="dw_agent",
            dag_id="bietlejuice.dw_agent__validation",
            cluster_path=Path("dags/agents/dw_agent/dw_agent_cluster.yml"),
        )

        outcome = asyncio.run(
            trigger_script.monitor_run(
                client,
                asyncio.Semaphore(1),
                printer,
                progress,
                dag,
                "manual__test",
                poll_interval=0,
                timeout=30,
                verbose=False,
                log_tail_lines=20,
            )
        )

        assert outcome.final_state == "success"
        assert outcome.dag_run_id == "manual__test"

    def test_retries_transient_poll_error(self) -> None:
        client = MagicMock()
        client.get_dag_run.side_effect = [
            requests.ConnectionError("network down"),
            {"state": "success"},
        ]
        client.list_task_instances.return_value = []

        printer = trigger_script.EventPrinter(
            stdout=io.StringIO(),
            stderr=io.StringIO(),
        )
        progress = trigger_script.ProgressTracker(total=1)

        outcome = asyncio.run(
            trigger_script.monitor_run(
                client,
                asyncio.Semaphore(1),
                printer,
                progress,
                _sample_dag(),
                "manual__test",
                poll_interval=0,
                timeout=30,
                verbose=False,
                log_tail_lines=20,
            )
        )

        assert outcome.final_state == "success"
        assert client.get_dag_run.call_count == 2

    def test_skip_increments_skipped_without_touching_active(self) -> None:
        progress = trigger_script.ProgressTracker(total=10)
        asyncio.run(progress.mark_triggered())
        asyncio.run(progress.mark_triggered())
        asyncio.run(progress.mark_outcome("skipped", release_active_slot=False))
        successful, failed, skipped, total, active = asyncio.run(progress.snapshot())
        assert successful == 0
        assert failed == 0
        assert skipped == 1
        assert active == 2
        assert total == 10

    def test_failure_marks_completed_before_status_event(self) -> None:
        client = MagicMock()
        client.get_dag_run.return_value = {"state": "failed"}
        client.list_task_instances.return_value = []

        stdout = io.StringIO()
        printer = trigger_script.EventPrinter(stdout=stdout, stderr=io.StringIO())
        progress = trigger_script.ProgressTracker(total=131)
        asyncio.run(progress.mark_triggered())

        outcome = asyncio.run(
            trigger_script.monitor_run(
                client,
                asyncio.Semaphore(1),
                printer,
                progress,
                _sample_dag(),
                "manual__test",
                poll_interval=0,
                timeout=30,
                verbose=False,
                log_tail_lines=20,
                fetch_failure_logs=False,
            )
        )

        assert outcome.final_state == "failed"
        successful, failed, skipped, total, active = asyncio.run(progress.snapshot())
        assert successful == 0
        assert failed == 1
        assert skipped == 0
        assert active == 0
        assert total == 131
        assert "0/1/0/131" in stdout.getvalue()

    def test_monitor_failure_fetches_logs(self) -> None:
        client = MagicMock()
        client.get_dag_run.return_value = {"state": "failed"}
        client.list_task_instances.return_value = [
            {"task_id": "load-dw", "state": "failed", "try_number": 1}
        ]
        client.get_task_log.return_value = "boom\nstack trace"

        stderr = io.StringIO()
        printer = trigger_script.EventPrinter(stdout=io.StringIO(), stderr=stderr)
        progress = trigger_script.ProgressTracker(total=1)
        dag = discovery.ValidationDag(
            line="agents",
            dag_name="dw_agent",
            dag_id="bietlejuice.dw_agent__validation",
            cluster_path=Path("dags/agents/dw_agent/dw_agent_cluster.yml"),
        )

        outcome = asyncio.run(
            trigger_script.monitor_run(
                client,
                asyncio.Semaphore(1),
                printer,
                progress,
                dag,
                "manual__test",
                poll_interval=0,
                timeout=30,
                verbose=False,
                log_tail_lines=20,
            )
        )

        assert outcome.final_state == "failed"
        assert "load-dw" in stderr.getvalue()
        assert "stack trace" in stderr.getvalue()


def _plan_with_conf(
    dag: discovery.ValidationDag | None = None,
    conf: dict[str, str] | None = None,
) -> trigger_script.DagExecutionPlan:
    return trigger_script.DagExecutionPlan(
        dag=dag or _sample_dag(),
        conf=conf or EXPECTED_CONF,
    )


class TestProdRunResolution:
    def test_conf_wins_over_interval(self) -> None:
        run = {
            "conf": {
                "load_start_date": "2026-06-01",
                "load_end_date": "2026-06-02",
            },
            "data_interval_start": "2026-05-20T03:00:00+00:00",
            "data_interval_end": "2026-05-27T03:00:00+00:00",
        }
        result = trigger_script._load_window_from_prod_dag_run(run)
        assert result is not None
        conf, source = result
        assert conf["load_start_date"] == "2026-06-01"
        assert conf["load_end_date"] == "2026-06-02"
        assert source == "conf"

    def test_interval_exclusive_end(self) -> None:
        run = {
            "conf": {},
            "data_interval_start": "2026-05-20T03:00:00+00:00",
            "data_interval_end": "2026-05-27T03:00:00+00:00",
        }
        result = trigger_script._load_window_from_prod_dag_run(run)
        assert result is not None
        conf, source = result
        assert conf["load_start_date"] == "2026-05-20"
        assert conf["load_end_date"] == "2026-05-26"
        assert source == "data_interval"

    def test_bumps_load_end_when_equal_to_start(self) -> None:
        run = {
            "conf": {
                "load_start_date": "2026-06-01",
                "load_end_date": "2026-06-01",
            },
        }
        result = trigger_script._load_window_from_prod_dag_run(run)
        assert result is not None
        conf, source = result
        assert conf["load_start_date"] == "2026-06-01"
        assert conf["load_end_date"] == "2026-06-02"
        assert source == "conf"

    def test_selects_fastest_run_in_lookback(self) -> None:
        now = datetime(2026, 6, 2, tzinfo=timezone.utc)
        runs = [
            {
                "dag_run_id": "slow",
                "start_date": "2026-05-28T03:00:00+00:00",
                "end_date": "2026-05-28T04:00:00+00:00",
            },
            {
                "dag_run_id": "too_fast",
                "start_date": "2026-05-29T03:00:00+00:00",
                "end_date": "2026-05-29T03:05:00+00:00",
            },
            {
                "dag_run_id": "fastest_qualifying",
                "start_date": "2026-05-30T03:00:00+00:00",
                "end_date": "2026-05-30T03:12:00+00:00",
            },
            {
                "dag_run_id": "medium",
                "start_date": "2026-05-31T03:00:00+00:00",
                "end_date": "2026-05-31T03:20:00+00:00",
            },
        ]
        selected = trigger_script._select_reference_prod_run(
            runs, lookback_days=14, now=now
        )
        assert selected is not None
        assert (
            trigger_script._dag_run_id_from_payload(selected) == "fastest_qualifying"
        )

    def test_tie_duration_prefers_latest_start(self) -> None:
        now = datetime(2026, 6, 2, tzinfo=timezone.utc)
        runs = [
            {
                "dag_run_id": "older",
                "start_date": "2026-05-28T03:00:00+00:00",
                "end_date": "2026-05-28T03:12:00+00:00",
            },
            {
                "dag_run_id": "newer",
                "start_date": "2026-05-30T03:00:00+00:00",
                "end_date": "2026-05-30T03:12:00+00:00",
            },
        ]
        selected = trigger_script._select_reference_prod_run(
            runs, lookback_days=14, now=now
        )
        assert trigger_script._dag_run_id_from_payload(selected) == "newer"

    def test_recency_skip(self) -> None:
        client = MagicMock()
        old_end = (datetime.now(timezone.utc) - timedelta(days=10)).isoformat()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "old",
                "start_date": old_end,
                "end_date": old_end,
                "conf": EXPECTED_CONF,
            }
        ]
        args = trigger_script._parse_args(["--from-prod-run"])
        plan = trigger_script._resolve_prod_run_plan(client, _sample_dag(), args)
        assert plan.conf is None
        assert "past 7 days" in (plan.skip_reason or "")

    def test_ignores_prod_runs_shorter_than_eight_minutes(self) -> None:
        now = datetime(2026, 6, 2, tzinfo=timezone.utc)
        runs = [
            {
                "dag_run_id": "noop",
                "start_date": "2026-06-01T03:00:00+00:00",
                "end_date": "2026-06-01T03:00:30+00:00",
                "conf": EXPECTED_CONF,
            }
        ]
        selected = trigger_script._select_reference_prod_run(
            runs, lookback_days=14, now=now
        )
        assert selected is None

        client = MagicMock()
        client.list_dag_runs.return_value = runs
        args = trigger_script._parse_args(
            ["--from-prod-run", "--no-prod-run-recency-filter"]
        )
        plan = trigger_script._resolve_prod_run_plan(
            client, _sample_dag(), args, now=now
        )
        assert plan.conf is None
        assert "at least 8m" in (plan.skip_reason or "")

    def test_recency_ignores_short_prod_runs(self) -> None:
        now = datetime(2026, 6, 2, tzinfo=timezone.utc)
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "noop",
                "start_date": "2026-06-01T03:00:00+00:00",
                "end_date": "2026-06-01T03:00:30+00:00",
                "conf": EXPECTED_CONF,
            }
        ]
        args = trigger_script._parse_args(["--from-prod-run"])
        plan = trigger_script._resolve_prod_run_plan(
            client, _sample_dag(), args, now=now
        )
        assert plan.conf is None
        assert "past 7 days" in (plan.skip_reason or "")

    def test_no_recency_filter_allows_stale_prod(self) -> None:
        client = MagicMock()
        old_start = (datetime.now(timezone.utc) - timedelta(days=10)).isoformat()
        old_end = (
            datetime.now(timezone.utc) - timedelta(days=10, hours=-1)
        ).isoformat()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "old",
                "start_date": old_start,
                "end_date": old_end,
                "conf": EXPECTED_CONF,
            }
        ]
        args = trigger_script._parse_args(
            ["--from-prod-run", "--no-prod-run-recency-filter"]
        )
        plan = trigger_script._resolve_prod_run_plan(client, _sample_dag(), args)
        assert plan.conf is not None
        assert plan.conf["load_start_date"] == EXPECTED_CONF["load_start_date"]
        assert plan.conf["load_end_date"] == EXPECTED_CONF["load_end_date"]
        assert plan.conf["reference_prod_dag_run_id"] == "old"
        assert plan.conf["window_source"] == "conf"


class TestDryRunTable:
    def test_prints_resolved_parameters(
        self, capsys: pytest.CaptureFixture[str]
    ) -> None:
        plans = [
            trigger_script.DagExecutionPlan(
                dag=_sample_dag(),
                conf=EXPECTED_CONF,
                prod_dag_run_id="scheduled__2026-06-01",
                prod_duration_seconds=530.0,
                window_source="conf",
                validation_action=trigger_script.RunAction(
                    action="trigger",
                    dag_run_id=None,
                    reason="no matching active run",
                ),
            )
        ]
        trigger_script._print_dry_run_table(plans)
        output = capsys.readouterr().out
        assert "2024-01-01" in output
        assert "TRIGGER" in output
        assert "scheduled__2026-06-01" in output


class TestTriggerAndMonitorFailureHandling:
    def test_failure_frees_parallel_slot_before_log_fetch(self) -> None:
        log_fetch_started = threading.Event()
        release_log_fetch = threading.Event()

        def get_dag_run(dag_id: str, dag_run_id: str) -> dict:
            return {"state": "failed"}

        def list_task_instances(dag_id: str, dag_run_id: str) -> list[dict]:
            log_fetch_started.set()
            release_log_fetch.wait(timeout=5)
            return [{"task_id": "load", "state": "failed", "try_number": 1}]

        client = MagicMock()
        client.list_dag_runs.return_value = []
        client.ensure_dag_unpaused.return_value = False
        client.trigger_dag_run.side_effect = (
            lambda dag_id, conf: {"dag_run_id": f"run__{dag_id}"}
        )
        client.get_dag_run.side_effect = get_dag_run
        client.list_task_instances.side_effect = list_task_instances
        client.get_task_log.return_value = "boom"

        dags = [
            discovery.ValidationDag(
                line="agents",
                dag_name=f"dag_{index}",
                dag_id=f"bietlejuice.dag_{index}__validation",
                cluster_path=Path(f"dags/agents/dag_{index}/dag_{index}_cluster.yml"),
            )
            for index in range(3)
        ]

        async def run_batch() -> list[trigger_script.RunOutcome]:
            task = asyncio.create_task(
                trigger_script.trigger_and_monitor(
                    client,
                    [_plan_with_conf(dag=dag) for dag in dags],
                    max_parallel=2,
                    max_runs=1,
                    force_retrigger=False,
                    dag_runs_lookback=25,
                    poll_interval=0,
                    timeout=30,
                    verbose=False,
                    log_tail_lines=20,
                )
            )
            for _ in range(200):
                await asyncio.sleep(0.01)
                if (
                    log_fetch_started.is_set()
                    and client.trigger_dag_run.call_count >= 3
                ):
                    break
            assert log_fetch_started.is_set()
            assert client.trigger_dag_run.call_count == 3
            release_log_fetch.set()
            return await task

        outcomes = asyncio.run(run_batch())

        assert len(outcomes) == 3
        assert all(outcome.final_state == "failed" for outcome in outcomes)


class TestTriggerAndMonitorResume:
    def test_resumes_running_dag_without_trigger(self) -> None:
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "run__existing",
                "state": "running",
                "start_date": "2024-01-02T00:00:00Z",
                "conf": EXPECTED_CONF,
            }
        ]
        client.get_dag_run.side_effect = [
            {"state": "running"},
            {"state": "success"},
        ]
        client.list_task_instances.return_value = []

        outcomes = asyncio.run(
            trigger_script.trigger_and_monitor(
                client,
                [_plan_with_conf()],
                max_parallel=1,
                max_runs=1,
                force_retrigger=False,
                dag_runs_lookback=25,
                poll_interval=0,
                timeout=30,
                verbose=False,
                log_tail_lines=20,
            )
        )

        assert outcomes[0].final_state == "success"
        client.trigger_dag_run.assert_not_called()
        client.ensure_dag_unpaused.assert_not_called()
        client.get_dag.assert_not_called()
        client.set_dag_paused.assert_not_called()

    def test_skips_already_validated_dag(self) -> None:
        client = MagicMock()
        client.list_dag_runs.return_value = [
            {
                "dag_run_id": "run__ok",
                "state": "success",
                "start_date": "2024-01-02T00:00:00Z",
                "conf": EXPECTED_CONF,
            }
        ]

        outcomes = asyncio.run(
            trigger_script.trigger_and_monitor(
                client,
                [_plan_with_conf()],
                max_parallel=1,
                max_runs=1,
                force_retrigger=False,
                dag_runs_lookback=25,
                poll_interval=0,
                timeout=30,
                verbose=False,
                log_tail_lines=20,
            )
        )

        assert outcomes[0].final_state == "skipped"
        client.trigger_dag_run.assert_not_called()
        client.get_dag_run.assert_not_called()


class TestMaxParallel:
    def test_caps_concurrent_runs_in_flight(self) -> None:
        active_runs: set[str] = set()
        peak_in_flight = 0
        lock = threading.Lock()

        def trigger_dag_run(dag_id: str, conf: dict) -> dict:
            nonlocal peak_in_flight
            with lock:
                active_runs.add(dag_id)
                peak_in_flight = max(peak_in_flight, len(active_runs))
            time.sleep(0.05)
            return {"dag_run_id": f"run__{dag_id}"}

        poll_counts: dict[str, int] = {}

        def get_dag_run(dag_id: str, dag_run_id: str) -> dict:
            poll_counts[dag_id] = poll_counts.get(dag_id, 0) + 1
            if poll_counts[dag_id] < 2:
                return {"state": "running"}
            with lock:
                active_runs.discard(dag_id)
            return {"state": "success"}

        client = MagicMock()
        client.list_dag_runs.return_value = []
        client.ensure_dag_unpaused.return_value = False
        client.trigger_dag_run.side_effect = trigger_dag_run
        client.get_dag_run.side_effect = get_dag_run
        client.list_task_instances.return_value = []

        dags = [
            discovery.ValidationDag(
                line="agents",
                dag_name=f"dag_{index}",
                dag_id=f"bietlejuice.dag_{index}__validation",
                cluster_path=Path(f"dags/agents/dag_{index}/dag_{index}_cluster.yml"),
            )
            for index in range(5)
        ]

        outcomes = asyncio.run(
            trigger_script.trigger_and_monitor(
                client,
                [_plan_with_conf(dag=dag) for dag in dags],
                max_parallel=2,
                max_runs=1,
                force_retrigger=False,
                dag_runs_lookback=25,
                poll_interval=0,
                timeout=30,
                verbose=False,
                log_tail_lines=20,
            )
        )

        assert peak_in_flight <= 2
        assert len(outcomes) == 5
        assert all(outcome.final_state == "success" for outcome in outcomes)
        assert client.trigger_dag_run.call_count == 5


class TestUnpauseBeforeTrigger:
    def _run_trigger(self, client: MagicMock) -> list[trigger_script.RunOutcome]:
        client.list_dag_runs.return_value = []
        client.trigger_dag_run.return_value = {"dag_run_id": "run__new"}
        client.get_dag_run.return_value = {"state": "success"}
        client.list_task_instances.return_value = []
        return asyncio.run(
            trigger_script.trigger_and_monitor(
                client,
                [_plan_with_conf()],
                max_parallel=1,
                max_runs=1,
                force_retrigger=False,
                dag_runs_lookback=25,
                poll_interval=0,
                timeout=30,
                verbose=False,
                log_tail_lines=20,
            )
        )

    def test_unpauses_before_trigger_when_paused(self) -> None:
        client = MagicMock()

        def ensure_unpause(dag_id: str) -> bool:
            dag = client.get_dag(dag_id)
            if dag.get("is_paused"):
                client.set_dag_paused(dag_id, is_paused=False)
                return True
            return False

        client.get_dag.return_value = {"is_paused": True}
        client.ensure_dag_unpaused.side_effect = ensure_unpause

        outcomes = self._run_trigger(client)

        assert outcomes[0].final_state == "success"
        client.get_dag.assert_called_once_with(_sample_dag().dag_id)
        client.set_dag_paused.assert_called_once_with(
            _sample_dag().dag_id, is_paused=False
        )
        client.trigger_dag_run.assert_called_once()
        assert client.method_calls.index(
            call.set_dag_paused(_sample_dag().dag_id, is_paused=False)
        ) < client.method_calls.index(
            call.trigger_dag_run(_sample_dag().dag_id, EXPECTED_CONF)
        )

    def test_skips_unpause_when_already_active(self) -> None:
        client = MagicMock()

        def ensure_unpause(dag_id: str) -> bool:
            dag = client.get_dag(dag_id)
            if dag.get("is_paused"):
                client.set_dag_paused(dag_id, is_paused=False)
                return True
            return False

        client.get_dag.return_value = {"is_paused": False}
        client.ensure_dag_unpaused.side_effect = ensure_unpause

        outcomes = self._run_trigger(client)

        assert outcomes[0].final_state == "success"
        client.get_dag.assert_called_once_with(_sample_dag().dag_id)
        client.set_dag_paused.assert_not_called()
        client.trigger_dag_run.assert_called_once()


class TestCliList:
    def test_list_mode(self, sample_dags_root: Path) -> None:
        stdout = io.StringIO()
        with patch.object(sys, "stdout", stdout):
            code = trigger_script.main(["--list", "--dags-root", str(sample_dags_root)])

        assert code == 0
        assert "bietlejuice.dw_agent__validation" in stdout.getvalue()

class TestEffectiveRunTimeout:
    def test_prod_duration_none_uses_base(self):
        plan = trigger_script.DagExecutionPlan(
            dag=_sample_dag(),
            conf=None,
            prod_duration_seconds=None,
        )
        assert trigger_script._effective_run_timeout(plan, 7200) == 7200

    def test_prod_duration_below_base_uses_base(self):
        plan = trigger_script.DagExecutionPlan(
            dag=_sample_dag(),
            conf=None,
            prod_duration_seconds=1000.0,
        )
        assert trigger_script._effective_run_timeout(plan, 7200) == 7200

    def test_prod_duration_above_base_scales(self):
        plan = trigger_script.DagExecutionPlan(
            dag=_sample_dag(),
            conf=None,
            prod_duration_seconds=6000.0,
        )
        assert trigger_script._effective_run_timeout(plan, 7200) == 12000

