import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT))

from scripts import cluster_validation_conf_exceptions as exc  # noqa: E402
from scripts import cluster_validation_reference as ref  # noqa: E402


class TestText2filterEvalsConfException:
    def test_interval_only_uses_single_ingest_day(self) -> None:
        run = {
            "data_interval_start": "2026-06-05T03:37:00+00:00",
            "data_interval_end": "2026-06-06T03:37:00+00:00",
        }
        result = exc.resolve_text2filter_evals_conf(run)
        assert result is not None
        conf, source = result
        assert conf["load_start_date"] == "2026-06-05"
        assert conf["load_end_date"] == "2026-06-06"
        assert source == "exception:text2filter_single_day"

    def test_conf_load_start_wins(self) -> None:
        run = {
            "conf": {"load_start_date": "2026-06-02", "load_end_date": "2026-06-04"},
            "data_interval_start": "2026-06-05T03:37:00+00:00",
            "data_interval_end": "2026-06-06T03:37:00+00:00",
        }
        result = exc.resolve_text2filter_evals_conf(run)
        assert result is not None
        conf, source = result
        assert conf["load_start_date"] == "2026-06-02"
        assert conf["load_end_date"] == "2026-06-03"
        assert source == "exception:text2filter_single_day"


class TestCyberLegalConfException:
    def test_interval_uses_three_day_window(self) -> None:
        run = {
            "data_interval_start": "2026-06-12T08:00:00+00:00",
            "data_interval_end": "2026-06-13T08:00:00+00:00",
        }
        result = exc.resolve_cyber_legal_conf(run)
        assert result is not None
        conf, source = result
        assert conf["load_start_date"] == "2026-06-12"
        assert conf["load_end_date"] == "2026-06-14"
        assert source == "exception:cyber_legal_3day_window"

    def test_conf_override_wins(self) -> None:
        run = {
            "conf": {
                "load_start_date": "2026-06-01",
                "load_end_date": "2026-06-03",
            },
            "data_interval_start": "2026-06-12T08:00:00+00:00",
            "data_interval_end": "2026-06-13T08:00:00+00:00",
        }
        result = exc.resolve_cyber_legal_conf(run)
        assert result is not None
        conf, source = result
        assert conf["load_start_date"] == "2026-06-01"
        assert conf["load_end_date"] == "2026-06-03"
        assert source == "conf"


class TestResolveValidationConfForDag:
    def test_unregistered_dag_uses_generic_resolver(self) -> None:
        run = {
            "data_interval_start": "2026-05-20T03:00:00+00:00",
            "data_interval_end": "2026-05-27T03:00:00+00:00",
        }
        generic = ref.load_window_from_prod_dag_run(run)
        resolved = exc.resolve_validation_conf_for_dag(
            "bietlejuice.some_other_dag", run
        )
        assert resolved == generic

    def test_text2filter_registered(self) -> None:
        run = {
            "data_interval_start": "2026-06-05T03:37:00+00:00",
            "data_interval_end": "2026-06-06T03:37:00+00:00",
        }
        result = exc.resolve_validation_conf_for_dag(
            exc.DAG_TEXT2FILTER_EVALS, run
        )
        assert result is not None
        _, source = result
        assert source == "exception:text2filter_single_day"
