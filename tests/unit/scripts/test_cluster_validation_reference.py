import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT))

from scripts import cluster_validation_reference as ref  # noqa: E402


class TestLoadWindowFromProdDagRun:
    def test_conf_wins_over_interval(self) -> None:
        run = {
            "conf": {
                "load_start_date": "2026-06-01",
                "load_end_date": "2026-06-02",
            },
            "data_interval_start": "2026-05-20T03:00:00+00:00",
            "data_interval_end": "2026-05-27T03:00:00+00:00",
        }
        result = ref.load_window_from_prod_dag_run(run)
        assert result is not None
        conf, source = result
        assert conf["load_start_date"] == "2026-06-01"
        assert conf["load_end_date"] == "2026-06-02"
        assert source == "conf"

    def test_interval_exclusive_end(self) -> None:
        run = {
            "data_interval_start": "2026-05-20T03:00:00+00:00",
            "data_interval_end": "2026-05-27T03:00:00+00:00",
        }
        result = ref.load_window_from_prod_dag_run(run)
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
        result = ref.load_window_from_prod_dag_run(run)
        assert result is not None
        conf, source = result
        assert conf["load_start_date"] == "2026-06-01"
        assert conf["load_end_date"] == "2026-06-02"
        assert source == "conf"


class TestSelectReferenceProdRun:
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
        selected = ref.select_reference_prod_run(runs, lookback_days=14, now=now)
        assert selected is not None
        assert ref.dag_run_id_from_payload(selected) == "fastest_qualifying"

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
        selected = ref.select_reference_prod_run(runs, lookback_days=14, now=now)
        assert ref.dag_run_id_from_payload(selected) == "newer"

    def test_ignores_prod_runs_shorter_than_eight_minutes(self) -> None:
        now = datetime(2026, 6, 2, tzinfo=timezone.utc)
        runs = [
            {
                "dag_run_id": "noop",
                "start_date": "2026-06-01T03:00:00+00:00",
                "end_date": "2026-06-01T03:00:30+00:00",
            }
        ]
        selected = ref.select_reference_prod_run(runs, lookback_days=14, now=now)
        assert selected is None


class TestValidationConfWithReference:
    def test_adds_reference_fields(self) -> None:
        conf = {
            "run_type": "test_run",
            "load_start_date": "2026-06-01",
            "load_end_date": "2026-06-02",
        }
        enriched = ref.validation_conf_with_reference(
            conf,
            reference_prod_dag_run_id="manual__2026-05-31",
            reference_prod_duration_seconds=774.2,
            window_source="conf",
        )
        assert enriched["reference_prod_dag_run_id"] == "manual__2026-05-31"
        assert enriched["reference_prod_duration_seconds"] == "774.2"
        assert enriched["window_source"] == "conf"
        assert enriched["load_start_date"] == "2026-06-01"
