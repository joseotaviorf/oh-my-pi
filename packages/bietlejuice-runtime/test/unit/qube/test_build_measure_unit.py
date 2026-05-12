"""
Unit tests for build_measure module functions.

These tests focus on testing individual functions in isolation,
making them easier to maintain and faster to run.
"""

from unittest.mock import MagicMock, Mock

from bietlejuice.qube.jobs.common.conf import Config
from bietlejuice.qube.jobs.measures.build_measure import (
    MeasureConfig,
    _apply_measure_filter,
    _calculate_window_range,
    _extract_distinct_entities,
    _extract_measure_config,
)


class TestExtractMeasureConfig:
    """Tests for _extract_measure_config function."""

    def test_extract_config_with_explicit_table(self):
        """Test extraction when table is explicitly specified."""
        spec = {
            "entity": "visit",
            "name": "unique_visits",
            "source": {
                "table": "custom.visit_table",
                "date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')",
            },
            "logic": {
                "filter_sql": "status = 'Done'",
            },
            "windows": [7, 28],
        }
        conf = Config(env="test", config_root="qube")
        conf.get_table_path = Mock(return_value="test_core.custom.visit_table")

        config = _extract_measure_config(spec, conf)

        assert config.entity == "visit"
        assert config.name == "unique_visits"
        assert config.windows == [7, 28]
        assert config.source_table == "test_core.custom.visit_table"
        assert config.entity_id_col == "id_visit"
        assert config.date_expr_sql == "unix_timestamp(dt_visit, 'yyyy-MM-dd')"
        assert config.filter_sql == "status = 'Done'"

    def test_extract_config_with_auto_derived_table(self):
        """Test extraction when table is auto-derived from entity."""
        spec = {
            "entity": "visit",
            "name": "unique_visits",
            "source": {
                "date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')",
            },
            "logic": {
                "filter_sql": "TRUE",
            },
        }
        conf = Config(env="test", config_root="qube")
        conf.get_table_path = Mock(return_value="test_core.visit")

        config = _extract_measure_config(spec, conf)

        assert config.source_table == "test_core.visit"
        assert config.entity_id_col == "id_visit"  # Auto-derived

    def test_extract_config_with_explicit_entity_id_col(self):
        """Test extraction when entity_id_col is explicitly specified."""
        spec = {
            "entity": "visit",
            "name": "unique_visits",
            "source": {
                "entity_id_col": "custom_id",
                "date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')",
            },
            "logic": {
                "filter_sql": "TRUE",
            },
        }
        conf = Config(env="test", config_root="qube")
        conf.get_table_path = Mock(return_value="test_core.visit")

        config = _extract_measure_config(spec, conf)

        assert config.entity_id_col == "custom_id"

    def test_extract_config_with_single_window(self):
        """Test extraction when window is a single integer."""
        spec = {
            "entity": "visit",
            "name": "unique_visits",
            "source": {"date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')"},
            "logic": {"filter_sql": "TRUE"},
            "windows": 7,
        }
        conf = Config(env="test", config_root="qube")
        conf.get_table_path = Mock(return_value="test_core.visit")

        config = _extract_measure_config(spec, conf)

        assert config.windows == [7]

    def test_extract_config_with_default_windows(self):
        """Test extraction when windows are not specified."""
        spec = {
            "entity": "visit",
            "name": "unique_visits",
            "source": {"date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')"},
            "logic": {"filter_sql": "TRUE"},
        }
        conf = Config(env="test", config_root="qube")
        conf.get_table_path = Mock(return_value="test_core.visit")

        config = _extract_measure_config(spec, conf)

        assert config.windows == [1, 7, 28]  # Default windows

    def test_extract_config_with_complex_filter(self):
        """Test extraction with complex filter SQL."""
        spec = {
            "entity": "visit",
            "name": "rent_visits",
            "source": {"date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')"},
            "logic": {
                "filter_sql": "business_context = 'RENT' AND status IN ('Done', 'Scheduled')"
            },
        }
        conf = Config(env="test", config_root="qube")
        conf.get_table_path = Mock(return_value="test_core.visit")

        config = _extract_measure_config(spec, conf)

        assert (
            config.filter_sql
            == "business_context = 'RENT' AND status IN ('Done', 'Scheduled')"
        )


class TestCalculateWindowRange:
    """Tests for _calculate_window_range function."""

    def test_calculate_window_range_7_days(self):
        """Test window range calculation for 7 days."""
        fixed_hi = 1751155200  # 2025-06-29 00:00:00
        window_days = 7

        hi, lo = _calculate_window_range(fixed_hi, window_days)

        assert hi == fixed_hi
        assert lo == fixed_hi - (7 * 86400)
        assert hi - lo == 7 * 86400

    def test_calculate_window_range_1_day(self):
        """Test window range calculation for 1 day."""
        fixed_hi = 1751155200
        window_days = 1

        hi, lo = _calculate_window_range(fixed_hi, window_days)

        assert hi == fixed_hi
        assert lo == fixed_hi - 86400

    def test_calculate_window_range_28_days(self):
        """Test window range calculation for 28 days."""
        fixed_hi = 1751155200
        window_days = 28

        hi, lo = _calculate_window_range(fixed_hi, window_days)

        assert hi == fixed_hi
        assert lo == fixed_hi - (28 * 86400)


class TestApplyMeasureFilter:
    """Tests for _apply_measure_filter function."""

    def test_apply_filter_calls_filter_method(self):
        """Test that _apply_measure_filter calls DataFrame.filter()."""
        from unittest.mock import patch

        mock_df = MagicMock()
        mock_df.filter.return_value = mock_df
        mock_df.count.return_value = 5

        # Mock F.expr to return a mock column
        with patch("bietlejuice.qube.jobs.measures.build_measure.F.expr") as mock_expr:
            mock_expr.return_value = MagicMock()

            result = _apply_measure_filter(mock_df, "status = 'Done'")

            # Should call F.expr with filter_sql
            mock_expr.assert_called_once_with("status = 'Done'")
            # Should call filter with the expression
            mock_df.filter.assert_called_once()
            assert result == mock_df

    def test_apply_filter_logs_count(self):
        """Test that filter logs the filtered count."""
        from unittest.mock import patch

        mock_df = MagicMock()
        mock_df.filter.return_value = mock_df
        mock_df.count.return_value = 3

        with patch("bietlejuice.qube.jobs.measures.build_measure.F.expr") as mock_expr:
            mock_expr.return_value = MagicMock()

            result = _apply_measure_filter(mock_df, "TRUE")

            # Should call count to log filtered rows
            mock_df.count.assert_called()
            assert result == mock_df


class TestExtractDistinctEntities:
    """Tests for _extract_distinct_entities function."""

    def test_extract_distinct_entities_calls_select_distinct(self):
        """Test that _extract_distinct_entities calls select and distinct."""
        from unittest.mock import patch

        mock_df = MagicMock()
        mock_df.select.return_value = mock_df
        mock_df.distinct.return_value = mock_df
        mock_df.withColumn.return_value = mock_df

        with (
            patch("bietlejuice.qube.jobs.measures.build_measure.F.col") as mock_col,
            patch("bietlejuice.qube.jobs.measures.build_measure.F.lit") as mock_lit,
        ):
            mock_col.return_value = MagicMock()
            mock_lit.return_value = MagicMock()

            result = _extract_distinct_entities(mock_df, "id_visit", 1751155200)

            # Should call F.col with entity_id_col
            mock_col.assert_called_once_with("id_visit")
            # Should select entity_id_col, get distinct, and add date
            mock_df.select.assert_called_once()
            mock_df.distinct.assert_called_once()
            mock_df.withColumn.assert_called_once()
            assert result == mock_df

    def test_extract_distinct_entities_adds_date_column(self):
        """Test that date column is added with correct format."""
        from unittest.mock import patch

        mock_df = MagicMock()
        mock_df.select.return_value = mock_df
        mock_df.distinct.return_value = mock_df
        mock_df.withColumn.return_value = mock_df

        with (
            patch("bietlejuice.qube.jobs.measures.build_measure.F.col") as mock_col,
            patch("bietlejuice.qube.jobs.measures.build_measure.F.lit") as mock_lit,
        ):
            mock_col.return_value = MagicMock()
            mock_lit.return_value = MagicMock()

            result = _extract_distinct_entities(mock_df, "id_visit", 1751155200)

            # Should add date column
            mock_df.withColumn.assert_called_once()
            call_args = mock_df.withColumn.call_args[0]
            assert call_args[0] == "date"
            assert result == mock_df


class TestMeasureConfigDataclass:
    """Tests for MeasureConfig dataclass."""

    def test_measure_config_creation(self):
        """Test creating MeasureConfig instance."""
        config = MeasureConfig(
            entity="visit",
            name="unique_visits",
            windows=[7, 28],
            source_table="core.visit",
            entity_id_col="id_visit",
            date_expr_sql="unix_timestamp(dt_visit, 'yyyy-MM-dd')",
            filter_sql="TRUE",
        )

        assert config.entity == "visit"
        assert config.name == "unique_visits"
        assert config.windows == [7, 28]
        assert config.source_table == "core.visit"
        assert config.entity_id_col == "id_visit"
        assert config.date_expr_sql == "unix_timestamp(dt_visit, 'yyyy-MM-dd')"
        assert config.filter_sql == "TRUE"

    def test_measure_config_immutability(self):
        """Test that MeasureConfig is a dataclass with proper attributes."""
        config = MeasureConfig(
            entity="visit",
            name="unique_visits",
            windows=[7],
            source_table="core.visit",
            entity_id_col="id_visit",
            date_expr_sql="unix_timestamp(dt_visit, 'yyyy-MM-dd')",
            filter_sql="TRUE",
        )

        # Should have all attributes
        assert hasattr(config, "entity")
        assert hasattr(config, "name")
        assert hasattr(config, "windows")
        assert hasattr(config, "source_table")
        assert hasattr(config, "entity_id_col")
        assert hasattr(config, "date_expr_sql")
        assert hasattr(config, "filter_sql")


class TestMeasureConfigAutoDerivation:
    """Tests for auto-derivation in measure config."""

    def test_auto_derive_table_from_entity(self):
        """Test that table is auto-derived as core.{entity}."""
        spec = {
            "entity": "contract",
            "name": "active_contracts",
            "source": {"date_expr": "unix_timestamp(ts_updated, 'yyyy-MM-dd')"},
            "logic": {"filter_sql": "status = 'Active'"},
        }
        conf = Config(env="test", config_root="qube")

        # Mock to capture what table path is requested
        called_with = []

        def mock_get_table_path(db_type, table_name):
            called_with.append((db_type, table_name))
            return f"test_{db_type}.{table_name}"

        conf.get_table_path = mock_get_table_path

        config = _extract_measure_config(spec, conf)

        # Should have called get_table_path with core_contract.contract
        assert len(called_with) == 1
        assert called_with[0] == ("core", "core_contract.contract")
        assert config.source_table == "test_core.core_contract.contract"

    def test_auto_derive_entity_id_col_from_entity(self):
        """Test that entity_id_col is auto-derived as id_{entity}."""
        spec = {
            "entity": "contract",
            "name": "active_contracts",
            "source": {"date_expr": "unix_timestamp(ts_updated, 'yyyy-MM-dd')"},
            "logic": {"filter_sql": "status = 'Active'"},
        }
        conf = Config(env="test", config_root="qube")
        conf.get_table_path = Mock(return_value="test_core.contract")

        config = _extract_measure_config(spec, conf)

        # Should auto-derive as id_contract
        assert config.entity_id_col == "id_contract"

    def test_explicit_table_overrides_auto_derivation(self):
        """Test that explicit table overrides auto-derivation."""
        spec = {
            "entity": "visit",
            "name": "unique_visits",
            "source": {
                "table": "custom_schema.custom_table",
                "date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')",
            },
            "logic": {"filter_sql": "TRUE"},
        }
        conf = Config(env="test", config_root="qube")

        called_with = []

        def mock_get_table_path(db_type, table_name):
            called_with.append((db_type, table_name))
            return f"test_{db_type}.{table_name}"

        conf.get_table_path = mock_get_table_path

        config = _extract_measure_config(  # pyright: ignore[reportUnusedVariable]
            spec, conf
        )

        # Should use explicit table
        assert called_with[0] == ("core", "custom_schema.custom_table")
        assert config.source_table == "test_core.custom_schema.custom_table"

    def test_explicit_entity_id_col_overrides_auto_derivation(self):
        """Test that explicit entity_id_col overrides auto-derivation."""
        spec = {
            "entity": "visit",
            "name": "unique_visits",
            "source": {
                "entity_id_col": "visit_uuid",
                "date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')",
            },
            "logic": {"filter_sql": "TRUE"},
        }
        conf = Config(env="test", config_root="qube")
        conf.get_table_path = Mock(return_value="test_core.visit")

        config = _extract_measure_config(spec, conf)

        # Should use explicit entity_id_col
        assert config.entity_id_col == "visit_uuid"
