"""
Unit tests for configuration management.
"""

import os
from unittest.mock import patch

from bietlejuice.qube.jobs.common.conf import Config, parse_common_args


class TestConfig:
    """Tests for Config class."""

    def test_config_defaults(self):
        """Test Config with default values."""
        config = Config()

        assert config.env == "dev"
        assert config.config_root == "qube/specs"
        assert config.db_prefix == ""
        assert config.core_db == "core"
        assert config.dim_db == "qube_dimensions"
        assert config.meas_db == "qube_measures"
        assert config.met_db == "qube_metrics"

    def test_config_custom_values(self):
        """Test Config with custom values."""
        config = Config(
            env="prod",
            config_root="/custom/specs",
            db_prefix="test_",
            warehouse="/custom/warehouse",
        )

        assert config.env == "prod"
        assert config.config_root == "/custom/specs"
        assert config.db_prefix == "test_"
        assert config.warehouse_path == "/custom/warehouse"
        # Prod environment should have Unity Catalog prefix
        assert config.core_db == "test_quintoandar_prod.core"
        assert config.dim_db == "test_quintoandar_prod.qube_dimensions"

    def test_config_db_prefix(self):
        """Test that db_prefix is applied to database names."""
        config = Config(db_prefix="test_")

        assert config.core_db == "test_core"
        assert config.dim_db == "test_qube_dimensions"
        assert config.meas_db == "test_qube_measures"
        assert config.met_db == "test_qube_metrics"

    @patch.dict(
        os.environ, {"QUBE_CORE_DB": "custom_core", "QUBE_DIM_DB": "custom_dim"}
    )
    def test_config_env_vars(self):
        """Test that environment variables override defaults."""
        config = Config()

        assert config.core_db == "custom_core"
        assert config.dim_db == "custom_dim"

    @patch.dict(os.environ, {"QUBE_WAREHOUSE_PATH": "/env/warehouse"})
    def test_config_warehouse_from_env(self):
        """Test warehouse path from environment variable."""
        config = Config(env="dev")

        assert config.warehouse_path == "/env/warehouse"

    def test_config_warehouse_default_dev(self):
        """Test default warehouse path for dev environment."""
        config = Config(env="dev", warehouse=None)

        # Should use default dev path if no env var
        assert config.warehouse_path == "/tmp/warehouse"

    def test_config_forno_environment(self):
        """Test Config for forno environment with Unity Catalog."""
        config = Config(env="forno")

        assert config.env == "forno"
        assert config.core_db == "quintoandar_forno.core"
        assert config.dim_db == "quintoandar_forno.qube_dimensions"
        assert config.meas_db == "quintoandar_forno.qube_measures"
        assert config.met_db == "quintoandar_forno.qube_metrics"
        assert config.warehouse_path == "s3a://5a-datalake-forno"

    def test_config_prod_environment(self):
        """Test Config for prod environment with Unity Catalog."""
        config = Config(env="prod")

        assert config.env == "prod"
        assert config.core_db == "quintoandar_prod.core"
        assert config.dim_db == "quintoandar_prod.qube_dimensions"
        assert config.meas_db == "quintoandar_prod.qube_measures"
        assert config.met_db == "quintoandar_prod.qube_metrics"
        assert config.warehouse_path == "s3a://5a-datalake-prod"

    def test_get_table_path_core(self):
        """Test get_table_path for core layer."""
        config = Config()

        assert config.get_table_path("core", "visit") == "core.visit"
        assert config.get_table_path("core", "contract") == "core.contract"

    def test_get_table_path_dim(self):
        """Test get_table_path for dimension layer."""
        config = Config()

        assert (
            config.get_table_path("dim", "visit__status__7d")
            == "qube_dimensions.visit__status__7d"
        )

    def test_get_table_path_meas(self):
        """Test get_table_path for measure layer."""
        config = Config()

        assert (
            config.get_table_path("meas", "visit__unique__7d")
            == "qube_measures.visit__unique__7d"
        )

    def test_get_table_path_met(self):
        """Test get_table_path for metric layer."""
        config = Config()

        assert (
            config.get_table_path("met", "visit__unique_rent__7d")
            == "qube_metrics.visit__unique_rent__7d"
        )

    def test_get_table_path_fully_qualified(self):
        """Test get_table_path with fully qualified table name."""
        config = Config()

        # If table already has a dot, return as-is
        assert (
            config.get_table_path("core", "custom_db.custom_table")
            == "custom_db.custom_table"
        )

    def test_get_table_path_unknown_layer(self):
        """Test get_table_path with unknown layer defaults to 'default'."""
        config = Config()

        assert config.get_table_path("unknown", "table") == "default.table"

    def test_get_table_path_with_prefix(self):
        """Test get_table_path with db_prefix."""
        config = Config(db_prefix="test_")

        assert (
            config.get_table_path("dim", "visit__status__7d")
            == "test_qube_dimensions.visit__status__7d"
        )

    def test_to_dict(self):
        """Test to_dict export."""
        config = Config(env="prod", db_prefix="test_", warehouse="/warehouse")
        result = config.to_dict()

        assert result["env"] == "prod"
        assert result["config_root"] == "qube/specs"
        # Prod environment includes Unity Catalog prefix
        assert result["core_db"] == "test_quintoandar_prod.core"
        assert result["dim_db"] == "test_quintoandar_prod.qube_dimensions"
        assert result["warehouse_path"] == "/warehouse"

    def test_get_schema_name_dev(self):
        """Test get_schema_name for dev environment (no catalog prefix)."""
        config = Config(env="dev")

        assert config.get_schema_name("core") == "core"
        assert config.get_schema_name("dim") == "qube_dimensions"
        assert config.get_schema_name("meas") == "qube_measures"
        assert config.get_schema_name("met") == "qube_metrics"

    def test_get_schema_name_forno(self):
        """Test get_schema_name for forno environment (with catalog prefix)."""
        config = Config(env="forno")

        # Should extract schema name without catalog prefix
        assert config.get_schema_name("core") == "core"
        assert config.get_schema_name("dim") == "qube_dimensions"
        assert config.get_schema_name("meas") == "qube_measures"
        assert config.get_schema_name("met") == "qube_metrics"

    def test_get_schema_name_prod(self):
        """Test get_schema_name for prod environment (with catalog prefix)."""
        config = Config(env="prod")

        # Should extract schema name without catalog prefix
        assert config.get_schema_name("core") == "core"
        assert config.get_schema_name("dim") == "qube_dimensions"
        assert config.get_schema_name("meas") == "qube_measures"
        assert config.get_schema_name("met") == "qube_metrics"


class TestParseCommonArgs:
    """Tests for parse_common_args function."""

    @patch("sys.argv", ["script.py", "--spec", "test.yaml"])
    def test_parse_common_args_required_spec(self):
        """Test that --spec is required."""
        args = parse_common_args("Test job")

        assert args.spec == "test.yaml"

    @patch("sys.argv", ["script.py", "--spec", "test.yaml", "--date", "2025-06-29"])
    def test_parse_common_args_date(self):
        """Test --date argument."""
        args = parse_common_args("Test job")

        assert args.date == "2025-06-29"

    @patch("sys.argv", ["script.py", "--spec", "test.yaml", "--env", "prod"])
    def test_parse_common_args_env(self):
        """Test --env argument."""
        args = parse_common_args("Test job")

        assert args.env == "prod"

    @patch("sys.argv", ["script.py", "--spec", "test.yaml", "--db-prefix", "test_"])
    def test_parse_common_args_db_prefix(self):
        """Test --db-prefix argument."""
        args = parse_common_args("Test job")

        assert args.db_prefix == "test_"

    @patch("sys.argv", ["script.py", "--spec", "test.yaml", "--log-level", "DEBUG"])
    def test_parse_common_args_log_level(self):
        """Test --log-level argument."""
        args = parse_common_args("Test job")

        assert args.log_level == "DEBUG"

    @patch("sys.argv", ["script.py", "--spec", "test.yaml", "--log-format", "json"])
    def test_parse_common_args_log_format(self):
        """Test --log-format argument."""
        args = parse_common_args("Test job")

        assert args.log_format == "json"

    @patch("sys.argv", ["script.py", "--spec", "test.yaml"])
    @patch.dict(os.environ, {"QUBE_ENV": "staging"})
    def test_parse_common_args_env_default(self):
        """Test that env defaults to QUBE_ENV or 'dev'."""
        args = parse_common_args("Test job")

        assert args.env == "staging"
