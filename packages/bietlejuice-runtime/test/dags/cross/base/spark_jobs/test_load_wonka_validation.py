"""Unit tests for load_wonka cluster validation env injection."""

import importlib.util
import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

_LOAD_WONKA_PATH = (
    Path(__file__).resolve().parents[7] / "dags/cross/base/spark_jobs/load_wonka.py"
)
_spec = importlib.util.spec_from_file_location("load_wonka", _LOAD_WONKA_PATH)
load_wonka = importlib.util.module_from_spec(_spec)
assert _spec.loader is not None
_spec.loader.exec_module(load_wonka)

WONKA_VALIDATION_TABLE_PREFIX = load_wonka.WONKA_VALIDATION_TABLE_PREFIX
apply_validation_env = load_wonka.apply_validation_env


class TestApplyValidationEnv:
    def test_sets_validation_env_vars(self, monkeypatch):
        monkeypatch.delenv("FEATURE_STORE_HISTORICAL_DATABASE", raising=False)
        monkeypatch.delenv("FEATURE_STORE_S3_BUCKET", raising=False)
        monkeypatch.delenv("WONKA_VALIDATION_TABLE_PREFIX", raising=False)

        validation_location = (
            "s3a://5a-datalake-prod/validation/cluster_validation/wonka"
        )
        with patch.object(
            load_wonka,
            "resolve_datalake_write_target",
            return_value=(
                "cluster_validation",
                "wonka___user_visits",
                validation_location,
            ),
        ):
            apply_validation_env(
                "cluster_validation",
                "wonka___user_visits",
                "5a-datalake-prod",
            )

        assert os.environ["FEATURE_STORE_HISTORICAL_DATABASE"] == "cluster_validation"
        assert (
            os.environ["FEATURE_STORE_S3_BUCKET"]
            == "5a-datalake-prod/validation/cluster_validation/wonka"
        )
        assert (
            os.environ["WONKA_VALIDATION_TABLE_PREFIX"] == WONKA_VALIDATION_TABLE_PREFIX
        )


class TestLoadWonkaMain:
    @patch.object(load_wonka, "apply_validation_env")
    @patch.object(load_wonka.importlib, "import_module")
    def test_validation_args_trigger_env_before_import(
        self, mock_import_module, mock_apply_validation_env, monkeypatch
    ):
        monkeypatch.setenv("DATABRICKS_S3_BUCKET", "5a-datalake-prod")

        mock_runner = MagicMock()
        mock_module = MagicMock()
        mock_module.runner = mock_runner
        mock_import_module.return_value = mock_module

        test_args = [
            "load_wonka.py",
            "user_visits.user_visits_runner.runner",
            "--target-database-name",
            "cluster_validation",
            "--target-table-name",
            "wonka___user_visits",
        ]
        with patch.object(sys, "argv", test_args):
            load_wonka.main()

        mock_apply_validation_env.assert_called_once_with(
            "cluster_validation",
            "wonka___user_visits",
            "5a-datalake-prod",
        )
        mock_runner.execute.assert_called_once()

    @patch.object(load_wonka, "apply_validation_env")
    @patch.object(load_wonka.importlib, "import_module")
    def test_prod_run_skips_validation_env(
        self, mock_import_module, mock_apply_validation_env
    ):
        mock_runner = MagicMock()
        mock_module = MagicMock()
        mock_module.runner = mock_runner
        mock_import_module.return_value = mock_module

        test_args = ["load_wonka.py", "user_visits.user_visits_runner.runner"]
        with patch.object(sys, "argv", test_args):
            load_wonka.main()

        mock_apply_validation_env.assert_not_called()
        mock_runner.execute.assert_called_once()

    def test_validation_requires_databricks_bucket(self, monkeypatch):
        monkeypatch.delenv("DATABRICKS_S3_BUCKET", raising=False)

        test_args = [
            "load_wonka.py",
            "user_visits.user_visits_runner.runner",
            "--target-database-name",
            "cluster_validation",
            "--target-table-name",
            "wonka___user_visits",
        ]
        with patch.object(sys, "argv", test_args):
            with pytest.raises(RuntimeError, match="DATABRICKS_S3_BUCKET"):
                load_wonka.main()
