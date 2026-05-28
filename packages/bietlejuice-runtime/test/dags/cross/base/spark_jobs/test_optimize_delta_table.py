"""Unit tests for build_year_month_day_predicate in optimize_delta_table."""

import sys
from unittest.mock import MagicMock, patch

import pytest

sys.modules["quintoandar_logger"] = MagicMock()
sys.modules["pyspark"] = MagicMock()
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["pyspark.sql.session"] = MagicMock()
sys.modules["pyspark.sql.functions"] = MagicMock()
sys.modules["pyspark.sql.context"] = MagicMock()
sys.modules["pyspark.context"] = MagicMock()
sys.modules["bietlejuice.base.spark"] = MagicMock()
sys.modules["bietlejuice.base.spark.base_spark"] = MagicMock()
sys.modules["bietlejuice.base.spark.runtime_detector"] = MagicMock()
sys.modules["bietlejuice.base.spark.spark_session_factory"] = MagicMock()
sys.modules["bietlejuice.base.db.metastore_mapping_factory"] = MagicMock()
sys.modules["bietlejuice.loaders.delta_loader"] = MagicMock()

from dags.cross.base.spark_jobs.optimize_delta_table import (  # noqa: E402
    MaintenanceStateConfig,
    _build_maintenance_state_config,
    _filter_tables_already_maintained,
    _resolve_partition_predicate,
    _should_use_daily_maintenance_cap,
    build_year_month_day_predicate,
    run_job,
)


class TestBuildYearMonthDayPredicate:
    def test_single_day_returns_plain_equality(self):
        predicate = build_year_month_day_predicate("2026-05-26", "2026-05-26")
        assert predicate == "year = 2026 AND month = 5 AND day = 26"

    def test_two_day_window_joins_with_or(self):
        predicate = build_year_month_day_predicate("2026-05-25", "2026-05-26")
        assert predicate == (
            "(year = 2026 AND month = 5 AND day = 25) OR "
            "(year = 2026 AND month = 5 AND day = 26)"
        )

    def test_crosses_month_boundary(self):
        predicate = build_year_month_day_predicate("2026-04-30", "2026-05-01")
        assert predicate == (
            "(year = 2026 AND month = 4 AND day = 30) OR "
            "(year = 2026 AND month = 5 AND day = 1)"
        )

    def test_end_before_start_raises(self):
        with pytest.raises(ValueError, match="must be on or after"):
            build_year_month_day_predicate("2026-05-26", "2026-05-25")

    def test_invalid_date_format_raises(self):
        with pytest.raises(ValueError, match="YYYY-MM-DD"):
            build_year_month_day_predicate("2026/05/26", "2026-05-26")


class TestResolvePartitionPredicate:
    def test_returns_none_when_start_missing(self):
        assert _resolve_partition_predicate(None, "2026-05-26") is None

    def test_returns_none_when_end_missing(self):
        assert _resolve_partition_predicate("2026-05-26", None) is None

    def test_returns_none_when_both_missing(self):
        assert _resolve_partition_predicate(None, None) is None

    def test_returns_predicate_when_both_present(self):
        assert (
            _resolve_partition_predicate("2026-05-26", "2026-05-26")
            == "year = 2026 AND month = 5 AND day = 26"
        )


class TestBuildMaintenanceStateConfig:
    @patch("dags.cross.base.spark_jobs.optimize_delta_table.ConfigurationService")
    def test_resolves_maintenance_settings_via_configuration_service(
        self, mock_configuration_service
    ):
        # arrange
        def get_config(key):
            return {
                "artifacts_bucket": "s3://artifacts.s3.data.quintoandar.com.br",
                "delta_maintenance_state_prefix": "bi-etl-ejuice/delta_maintenance",
                "aws_s3_region": "us-east-1",
            }[key]

        mock_configuration_service.return_value.get_config.side_effect = get_config
        args = type(
            "Args",
            (),
            {
                "dag_name": "my_dag",
                "environment": "forno",
                "maintenance_date": "2026-05-28",
                "state_prefix": None,
            },
        )()

        # act
        config = _build_maintenance_state_config(args)

        # assert
        mock_configuration_service.assert_called_once_with("my_dag")
        assert mock_configuration_service.return_value.get_config.call_count == 3
        assert config.state_bucket == "s3://artifacts.s3.data.quintoandar.com.br"
        assert config.state_prefix == "bi-etl-ejuice/delta_maintenance"
        assert config.region_name == "us-east-1"
        assert config.environment == "forno"
        assert config.is_enabled is True

    @patch("dags.cross.base.spark_jobs.optimize_delta_table.ConfigurationService")
    def test_cli_state_prefix_overrides_configuration_service(
        self, mock_configuration_service
    ):
        # arrange
        def get_config(key):
            return {
                "artifacts_bucket": "s3://artifacts-bucket",
                "delta_maintenance_state_prefix": "bi-etl-ejuice/delta_maintenance",
                "aws_s3_region": "us-east-1",
            }[key]

        mock_configuration_service.return_value.get_config.side_effect = get_config
        args = type(
            "Args",
            (),
            {
                "dag_name": "my_dag",
                "environment": "forno",
                "maintenance_date": "2026-05-28",
                "state_prefix": "custom/prefix",
            },
        )()

        # act
        config = _build_maintenance_state_config(args)

        # assert
        assert config.state_prefix == "custom/prefix"

    def test_skips_configuration_service_when_dag_name_missing(self):
        # arrange
        args = type(
            "Args",
            (),
            {
                "dag_name": None,
                "environment": "forno",
                "maintenance_date": "2026-05-28",
                "state_prefix": None,
            },
        )()

        # act
        config = _build_maintenance_state_config(args)

        # assert
        assert config.state_bucket is None
        assert config.state_prefix is None
        assert config.region_name is None
        assert config.is_enabled is False


class TestDailyMaintenanceCap:
    @pytest.fixture
    def maintenance_state(self):
        return MaintenanceStateConfig(
            state_bucket="s3://artifacts-bucket",
            environment="forno",
            maintenance_date="2026-05-28",
            dag_name="test_dag",
            state_prefix="bi-etl-ejuice/delta_maintenance",
            region_name="us-east-1",
        )

    def test_should_use_cap_when_enabled(self, maintenance_state):
        # arrange
        table_configs = {"maintenance_once_per_day": True, "run_optimize": True}

        # act
        use_cap = _should_use_daily_maintenance_cap(table_configs, maintenance_state)

        # assert
        assert use_cap is True

    def test_should_not_use_cap_when_opted_out(self, maintenance_state):
        # arrange
        table_configs = {"maintenance_once_per_day": False, "run_optimize": True}

        # act
        use_cap = _should_use_daily_maintenance_cap(table_configs, maintenance_state)

        # assert
        assert use_cap is False

    def test_should_not_use_cap_when_no_maintenance_commands(self, maintenance_state):
        # arrange
        table_configs = {
            "maintenance_once_per_day": True,
            "run_optimize": False,
            "run_vacuum": False,
        }

        # act
        use_cap = _should_use_daily_maintenance_cap(table_configs, maintenance_state)

        # assert
        assert use_cap is False

    @patch(
        "dags.cross.base.spark_jobs.optimize_delta_table._maintenance_marker_exists",
        return_value=True,
    )
    @patch("dags.cross.base.spark_jobs.optimize_delta_table.get_full_table_name")
    def test_filter_removes_tables_with_marker(
        self, mock_full_name, mock_marker_exists, maintenance_state
    ):
        # arrange
        mock_full_name.return_value = "datalake_dw.fact_x"
        tables = {
            "fact_x": {
                "schema": "dw",
                "maintenance_once_per_day": True,
                "run_optimize": True,
            },
        }

        # act
        remaining = _filter_tables_already_maintained(tables, "dw", maintenance_state)

        # assert
        assert remaining == {}

    @patch(
        "dags.cross.base.spark_jobs.optimize_delta_table._maintenance_marker_exists",
        return_value=False,
    )
    @patch("dags.cross.base.spark_jobs.optimize_delta_table.get_full_table_name")
    def test_filter_keeps_tables_without_marker(
        self, mock_full_name, mock_marker_exists, maintenance_state
    ):
        # arrange
        mock_full_name.return_value = "datalake_dw.fact_x"
        tables = {
            "fact_x": {
                "schema": "dw",
                "maintenance_once_per_day": True,
                "run_optimize": True,
            },
        }

        # act
        remaining = _filter_tables_already_maintained(tables, "dw", maintenance_state)

        # assert
        assert remaining == tables

    @patch(
        "dags.cross.base.spark_jobs.optimize_delta_table._maintenance_marker_exists",
        return_value=True,
    )
    @patch("dags.cross.base.spark_jobs.optimize_delta_table.write_maintenance_marker")
    @patch("dags.cross.base.spark_jobs.optimize_delta_table.get_full_table_name")
    def test_run_job_skips_when_marker_exists(
        self, mock_full_name, mock_write_marker, mock_marker_exists, maintenance_state
    ):
        # arrange
        mock_full_name.return_value = "datalake_dw.fact_x"
        loader = MagicMock()
        table_configs = {
            "schema": "dw",
            "maintenance_once_per_day": True,
            "run_optimize": True,
        }

        # act
        run_job(
            loader,
            "fact_x",
            table_configs,
            "dw",
            maintenance_state=maintenance_state,
        )

        # assert
        loader.optimize_table.assert_not_called()
        mock_write_marker.assert_not_called()

    @patch(
        "dags.cross.base.spark_jobs.optimize_delta_table._maintenance_marker_exists",
        return_value=False,
    )
    @patch("dags.cross.base.spark_jobs.optimize_delta_table.write_maintenance_marker")
    @patch("dags.cross.base.spark_jobs.optimize_delta_table.get_full_table_name")
    def test_run_job_writes_marker_after_success(
        self, mock_full_name, mock_write_marker, mock_marker_exists, maintenance_state
    ):
        # arrange
        mock_full_name.return_value = "datalake_dw.fact_x"
        loader = MagicMock()
        table_configs = {
            "schema": "dw",
            "maintenance_once_per_day": True,
            "run_optimize": True,
            "run_vacuum": True,
        }

        # act
        run_job(
            loader,
            "fact_x",
            table_configs,
            "dw",
            maintenance_state=maintenance_state,
        )

        # assert
        loader.optimize_table.assert_called_once()
        loader.vacuum_table.assert_called_once()
        mock_write_marker.assert_called_once()
