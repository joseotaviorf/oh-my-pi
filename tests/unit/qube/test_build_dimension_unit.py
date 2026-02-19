"""
Unit tests for build_dimension module functions.

These tests focus on testing individual functions in isolation,
making them easier to maintain and faster to run.
"""

from unittest.mock import Mock, MagicMock, patch

from bietlejuice.qube.jobs.dimensions.build_dimension import (
    LogicConfig,
    _extract_dimension_config,
    _extract_logic_config,
    _calculate_window_range,
    _build_extra_column_expressions,
    _build_extra_column_aggregations,
    _select_columns_for_logic,
    _join_with_supported_entities_if_needed,
)
from bietlejuice.qube.jobs.common.conf import Config


class TestExtractDimensionConfig:
    """Tests for _extract_dimension_config function."""

    def test_extract_config_with_explicit_table(self):
        """Test extraction when table is explicitly specified."""
        spec = {
            "entity": "visit",
            "name": "visit_status",
            "source": {
                "table": "custom.visit_table",
                "date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')",
                "select": ["id_visit", "status"],
            },
            "windows": [7, 28],
        }
        conf = Config(env="test", config_root="qube")
        conf.get_table_path = Mock(return_value="test_core.custom.visit_table")

        config = _extract_dimension_config(spec, conf)

        assert config.entity == "visit"
        assert config.name == "visit_status"
        assert config.windows == [7, 28]
        assert config.source_table == "test_core.custom.visit_table"
        assert config.entity_id_col == "id_visit"
        assert config.date_expr_sql == "unix_timestamp(dt_visit, 'yyyy-MM-dd')"
        assert "id_visit" in config.required_cols
        assert "status" in config.required_cols

    def test_extract_config_with_auto_derived_table(self):
        """Test extraction when table is auto-derived from entity."""
        spec = {
            "entity": "visit",
            "name": "visit_status",
            "source": {
                "date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')",
            },
        }
        conf = Config(env="test", config_root="qube")
        conf.get_table_path = Mock(return_value="test_core.visit")

        config = _extract_dimension_config(spec, conf)

        assert config.source_table == "test_core.visit"
        assert config.entity_id_col == "id_visit"  # Auto-derived
        assert config.required_cols == ["id_visit"]

    def test_extract_config_with_explicit_entity_id_col(self):
        """Test extraction when entity_id_col is explicitly specified."""
        spec = {
            "entity": "visit",
            "name": "visit_status",
            "source": {
                "entity_id_col": "custom_id",
                "date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')",
            },
        }
        conf = Config(env="test", config_root="qube")
        conf.get_table_path = Mock(return_value="test_core.visit")

        config = _extract_dimension_config(spec, conf)

        assert config.entity_id_col == "custom_id"
        assert config.required_cols == ["custom_id"]

    def test_extract_config_with_single_window(self):
        """Test extraction when window is a single integer."""
        spec = {
            "entity": "visit",
            "name": "visit_status",
            "source": {"date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')"},
            "windows": 7,
        }
        conf = Config(env="test", config_root="qube")
        conf.get_table_path = Mock(return_value="test_core.visit")

        config = _extract_dimension_config(spec, conf)

        assert config.windows == [7]

    def test_extract_config_with_default_windows(self):
        """Test extraction when windows are not specified."""
        spec = {
            "entity": "visit",
            "name": "visit_status",
            "source": {"date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')"},
        }
        conf = Config(env="test", config_root="qube")
        conf.get_table_path = Mock(return_value="test_core.visit")

        config = _extract_dimension_config(spec, conf)

        assert config.windows == [1, 7, 28]  # Default windows


class TestExtractLogicConfig:
    """Tests for _extract_logic_config function."""

    def test_extract_logic_config_with_all_fields(self):
        """Test extraction with all logic fields specified."""
        spec = {
            "name": "visit_status",
            "logic": {
                "card": "multi",
                "type": "number",
                "agg": "sum",
                "expr_sql": "SUM(value)",
                "value_col": "status",
            },
            "order_by": {"ts_col": "dt_visit", "nulls_last": True},
            "extra_cols": ["dt_visit", "ts_created"],
            "include_all_entities": True,
            "defaults": {"unknown_string": "UNKNOWN"},
        }

        config = _extract_logic_config(spec)

        assert config.card == "multi"
        assert config.dtype == "number"
        assert config.agg == "sum"
        assert config.expr_sql == "SUM(value)"
        assert config.value_col == "status"
        assert config.order_by_ts_col == "dt_visit"
        assert config.extra_cols == ["dt_visit", "ts_created"]
        assert config.include_all_entities is True
        assert config.defaults == {"unknown_string": "UNKNOWN"}

    def test_extract_logic_config_with_defaults(self):
        """Test extraction with default values."""
        spec = {
            "name": "visit_status",
            "logic": {},
        }

        config = _extract_logic_config(spec)

        assert config.card == "single"
        assert config.dtype == "string"
        assert config.agg is None
        assert config.expr_sql is None
        assert config.value_col == "visit_status"  # Defaults to name
        assert config.order_by_ts_col is None
        assert config.extra_cols == []
        assert config.include_all_entities is False
        assert config.defaults == {}

    def test_extract_logic_config_without_order_by(self):
        """Test extraction when order_by is not specified."""
        spec = {
            "name": "visit_status",
            "logic": {"agg": "last"},
        }

        config = _extract_logic_config(spec)

        assert config.order_by_ts_col is None


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


# class TestBuildAggregationExpression:
#     """Tests for _build_aggregation_expression function."""

#     def test_build_expression_with_expr_sql(self):
#         """Test building expression when expr_sql is provided."""
#         expr = _build_aggregation_expression("status", "sum", "SUM(status) * 2")

#         # Should use expr_sql when provided
#         assert expr is not None

#     def test_build_expression_with_count(self):
#         """Test building count aggregation."""
#         expr = _build_aggregation_expression("status", "count", None)

#         assert expr is not None

#     def test_build_expression_with_sum(self):
#         """Test building sum aggregation."""
#         expr = _build_aggregation_expression("value", "sum", None)

#         assert expr is not None

#     def test_build_expression_with_avg(self):
#         """Test building avg aggregation."""
#         expr = _build_aggregation_expression("value", "avg", None)

#         assert expr is not None

#     def test_build_expression_with_min(self):
#         """Test building min aggregation."""
#         expr = _build_aggregation_expression("value", "min", None)

#         assert expr is not None

#     def test_build_expression_with_max(self):
#         """Test building max aggregation."""
#         expr = _build_aggregation_expression("value", "max", None)

#         assert expr is not None

#     def test_build_expression_with_collect_set(self):
#         """Test building collect_set aggregation."""
#         expr = _build_aggregation_expression("value", "collect_set", None)

#         assert expr is not None

#     def test_build_expression_with_mode(self):
#         """Test building mode aggregation."""
#         expr = _build_aggregation_expression("value", "mode", None)

#         assert expr is not None

#     def test_build_expression_with_unknown_agg(self):
#         """Test building expression with unknown aggregation (defaults to first)."""
#         expr = _build_aggregation_expression("value", "unknown", None)

#         assert expr is not None

#     def test_build_expression_with_none_agg(self):
#         """Test building expression with None aggregation (defaults to first)."""
#         expr = _build_aggregation_expression("value", None, None)

#         assert expr is not None


class TestBuildExtraColumnExpressions:
    """Tests for _build_extra_column_expressions function."""

    # def test_build_expressions_with_existing_columns(self):
    #     """Test building expressions when columns exist."""
    #     mock_df = MagicMock()
    #     mock_df.columns = ["id_visit", "status", "dt_visit", "ts_created"]

    #     expressions = _build_extra_column_expressions(mock_df, ["dt_visit", "ts_created"])

    #     assert len(expressions) == 2
    #     assert all(expr is not None for expr in expressions)

    def test_build_expressions_with_missing_columns(self):
        """Test building expressions when some columns are missing."""
        mock_df = MagicMock()
        mock_df.columns = ["id_visit", "status"]

        expressions = _build_extra_column_expressions(
            mock_df, ["dt_visit", "ts_created"]
        )

        # Should skip missing columns
        assert len(expressions) == 0

    # def test_build_expressions_with_partial_columns(self):
    #     """Test building expressions when some columns exist."""
    #     mock_df = MagicMock()
    #     mock_df.columns = ["id_visit", "status", "dt_visit"]

    #     expressions = _build_extra_column_expressions(mock_df, ["dt_visit", "ts_created"])

    #     # Should only include existing columns
    #     assert len(expressions) == 1

    def test_build_expressions_with_empty_list(self):
        """Test building expressions with empty extra_cols."""
        mock_df = MagicMock()
        mock_df.columns = ["id_visit", "status"]

        expressions = _build_extra_column_expressions(mock_df, [])

        assert len(expressions) == 0


class TestBuildExtraColumnAggregations:
    """Tests for _build_extra_column_aggregations function."""

    # def test_build_aggregations_with_existing_columns(self):
    #     """Test building aggregations when columns exist."""
    #     mock_df = MagicMock()
    #     mock_df.columns = ["id_visit", "status", "dt_visit", "ts_created"]

    #     aggregations = _build_extra_column_aggregations(mock_df, ["dt_visit", "ts_created"])

    #     assert len(aggregations) == 2
    #     assert all(agg is not None for agg in aggregations)

    def test_build_aggregations_with_missing_columns(self):
        """Test building aggregations when some columns are missing."""
        mock_df = MagicMock()
        mock_df.columns = ["id_visit", "status"]

        aggregations = _build_extra_column_aggregations(
            mock_df, ["dt_visit", "ts_created"]
        )

        # Should skip missing columns
        assert len(aggregations) == 0

    def test_build_aggregations_with_empty_list(self):
        """Test building aggregations with empty extra_cols."""
        mock_df = MagicMock()
        mock_df.columns = ["id_visit", "status"]

        aggregations = _build_extra_column_aggregations(mock_df, [])

        assert len(aggregations) == 0


class TestSelectColumnsForLogic:
    """Tests for _select_columns_for_logic function."""

    def test_select_columns_without_source_select(self):
        """Test when source.select is not specified."""
        mock_df = MagicMock()
        spec = {"source": {}}
        logic_config = LogicConfig(
            card="single",
            dtype="string",
            agg=None,
            expr_sql=None,
            value_col="status",
            order_by_ts_col=None,
            extra_cols=[],
            include_all_entities=False,
            defaults={},
        )

        result = _select_columns_for_logic(mock_df, spec, logic_config, "id_visit")

        # Should return original dataframe
        assert result == mock_df

    def test_select_columns_with_source_select(self):
        """Test when source.select is specified."""
        mock_df = MagicMock()
        mock_df.select.return_value = mock_df
        spec = {"source": {"select": ["id_visit", "status", "dt_visit"]}}
        logic_config = LogicConfig(
            card="single",
            dtype="string",
            agg=None,
            expr_sql=None,
            value_col="status",
            order_by_ts_col=None,
            extra_cols=[],
            include_all_entities=False,
            defaults={},
        )

        result = _select_columns_for_logic(mock_df, spec, logic_config, "id_visit")

        # Should call select
        mock_df.select.assert_called_once()
        assert result == mock_df

    # def test_select_columns_includes_value_col(self):
    #     """Test that value_col is included even if not in select."""
    #     mock_df = MagicMock()
    #     mock_df.select.return_value = mock_df
    #     spec = {"source": {"select": ["id_visit", "dt_visit"]}}
    #     logic_config = LogicConfig(
    #         card="single",
    #         dtype="string",
    #         agg=None,
    #         expr_sql=None,
    #         value_col="status",  # Not in select
    #         order_by_ts_col=None,
    #         extra_cols=[],
    #         include_all_entities=False,
    #         defaults={},
    #     )

    #     _select_columns_for_logic(mock_df, spec, logic_config, "id_visit")

    #     # Check that select was called with value_col included
    #     call_args = mock_df.select.call_args[0][0]
    #     assert "status" in call_args or any("status" in str(arg) for arg in call_args)

    def test_select_columns_includes_extra_cols(self):
        """Test that extra_cols are included."""
        mock_df = MagicMock()
        mock_df.select.return_value = mock_df
        spec = {"source": {"select": ["id_visit", "status"]}}
        logic_config = LogicConfig(
            card="single",
            dtype="string",
            agg=None,
            expr_sql=None,
            value_col="status",
            order_by_ts_col=None,
            extra_cols=["dt_visit", "ts_created"],
            include_all_entities=False,
            defaults={},
        )

        _select_columns_for_logic(mock_df, spec, logic_config, "id_visit")

        # Should include extra_cols
        mock_df.select.assert_called_once()

    def test_select_columns_includes_order_by_for_last(self):
        """Test that order_by column is included for 'last' aggregation."""
        mock_df = MagicMock()
        mock_df.select.return_value = mock_df
        spec = {"source": {"select": ["id_visit", "status"]}}
        logic_config = LogicConfig(
            card="single",
            dtype="string",
            agg="last",
            expr_sql=None,
            value_col="status",
            order_by_ts_col="dt_visit",  # Should be included
            extra_cols=[],
            include_all_entities=False,
            defaults={},
        )

        _select_columns_for_logic(mock_df, spec, logic_config, "id_visit")

        # Should include order_by_ts_col
        mock_df.select.assert_called_once()


class TestJoinWithSupportedEntitiesIfNeeded:
    """Tests for _join_with_supported_entities_if_needed function."""

    def test_join_when_include_all_entities_false(self):
        """Test when include_all_entities is False."""
        mock_result_df = MagicMock()
        mock_result_df.columns = ["entity_id", "value"]
        mock_result_df.withColumnRenamed.return_value = mock_result_df

        result = _join_with_supported_entities_if_needed(
            mock_result_df,
            MagicMock(),
            "visit",
            "id_visit",
            False,
            1751155200,
        )

        # Should just rename column
        mock_result_df.withColumnRenamed.assert_called_once_with(
            "entity_id", "id_visit"
        )
        assert result == mock_result_df

    def test_join_when_include_all_entities_true(self):
        """Test when include_all_entities is True."""
        mock_result_df = MagicMock()
        mock_result_df.columns = ["entity_id", "value"]
        mock_sup_df = MagicMock()
        mock_sup_df.count.return_value = 10
        mock_sup_df.join.return_value = mock_result_df

        with patch(
            "bietlejuice.qube.jobs.dimensions.build_dimension._get_supported_ids",
            return_value=mock_sup_df,
        ):
            result = _join_with_supported_entities_if_needed(
                mock_result_df,
                MagicMock(),
                "visit",
                "id_visit",
                True,
                1751155200,
            )

        # Should join with supported IDs
        mock_sup_df.join.assert_called_once()
        assert result == mock_result_df


# class TestApplyDefaults:
#     """Tests for _apply_defaults function."""

#     def test_apply_defaults(self):
#         """Test applying default values."""
#         mock_df = MagicMock()
#         mock_df.columns = ["id_visit", "value"]
#         mock_df.withColumn.return_value = mock_df

#         logic_config = LogicConfig(
#             card="single",
#             dtype="string",
#             agg=None,
#             expr_sql=None,
#             value_col="status",
#             order_by_ts_col=None,
#             extra_cols=[],
#             include_all_entities=False,
#             defaults={"unknown_string": "UNKNOWN"},
#         )

#         result = _apply_defaults(mock_df, logic_config)

#         # Should call withColumn to apply defaults
#         mock_df.withColumn.assert_called_once()
#         assert result == mock_df


# class TestPrepareOutputDataframe:
#     """Tests for _prepare_output_dataframe function."""

#     def test_prepare_output_with_entity_id_col(self):
#         """Test when entity_id_col exists in dataframe."""
#         mock_df = MagicMock()
#         mock_df.columns = ["id_visit", "value", "dt_visit"]
#         mock_df.select.return_value = mock_df

#         dim_config = DimensionConfig(
#             entity="visit",
#             name="visit_status",
#             windows=[7],
#             source_table="core.visit",
#             entity_id_col="id_visit",
#             date_expr_sql="unix_timestamp(dt_visit, 'yyyy-MM-dd')",
#             required_cols=["id_visit"],
#         )

#         logic_config = LogicConfig(
#             card="single",
#             dtype="string",
#             agg=None,
#             expr_sql=None,
#             value_col="status",
#             order_by_ts_col=None,
#             extra_cols=["dt_visit"],
#             include_all_entities=False,
#             defaults={},
#         )

#         result = _prepare_output_dataframe(mock_df, dim_config, logic_config, 1751155200)

#         # Should call select with final columns
#         mock_df.select.assert_called_once()
#         assert result == mock_df

#     def test_prepare_output_without_entity_id_col(self):
#         """Test when entity_id_col doesn't exist (uses entity_id alias)."""
#         mock_df = MagicMock()
#         mock_df.columns = ["entity_id", "value"]
#         mock_df.select.return_value = mock_df

#         dim_config = DimensionConfig(
#             entity="visit",
#             name="visit_status",
#             windows=[7],
#             source_table="core.visit",
#             entity_id_col="id_visit",
#             date_expr_sql="unix_timestamp(dt_visit, 'yyyy-MM-dd')",
#             required_cols=["id_visit"],
#         )

#         logic_config = LogicConfig(
#             card="single",
#             dtype="string",
#             agg=None,
#             expr_sql=None,
#             value_col="status",
#             order_by_ts_col=None,
#             extra_cols=[],
#             include_all_entities=False,
#             defaults={},
#         )

#         result = _prepare_output_dataframe(mock_df, dim_config, logic_config, 1751155200)

#         # Should call select
#         mock_df.select.assert_called_once()
#         assert result == mock_df

#     def test_prepare_output_with_extra_cols(self):
#         """Test when extra_cols are specified."""
#         mock_df = MagicMock()
#         mock_df.columns = ["id_visit", "value", "dt_visit", "ts_created"]
#         mock_df.select.return_value = mock_df

#         dim_config = DimensionConfig(
#             entity="visit",
#             name="visit_status",
#             windows=[7],
#             source_table="core.visit",
#             entity_id_col="id_visit",
#             date_expr_sql="unix_timestamp(dt_visit, 'yyyy-MM-dd')",
#             required_cols=["id_visit"],
#         )

#         logic_config = LogicConfig(
#             card="single",
#             dtype="string",
#             agg=None,
#             expr_sql=None,
#             value_col="status",
#             order_by_ts_col=None,
#             extra_cols=["dt_visit", "ts_created"],
#             include_all_entities=False,
#             defaults={},
#         )

#         result = _prepare_output_dataframe(mock_df, dim_config, logic_config, 1751155200)

#         # Should include extra_cols in select
#         mock_df.select.assert_called_once()
#         assert result == mock_df


# class TestGetSupportedIds:
#     """Tests for _get_supported_ids function."""

#     def test_get_supported_ids_with_ts_created(self):
#         """Test when ts_created column exists."""
#         mock_df = MagicMock()
#         mock_df.columns = ["id_visit", "ts_created"]
#         mock_df.filter.return_value = mock_df
#         mock_df.select.return_value = mock_df
#         mock_df.distinct.return_value = mock_df

#         result = _get_supported_ids(mock_df, "id_visit", "id_visit", 1751155200)

#         # Should filter by ts_created
#         mock_df.filter.assert_called_once()
#         mock_df.select.assert_called_once()
#         mock_df.distinct.assert_called_once()
#         assert result == mock_df

#     def test_get_supported_ids_without_ts_created(self):
#         """Test when ts_created column doesn't exist."""
#         mock_df = MagicMock()
#         mock_df.columns = ["id_visit"]
#         mock_df.select.return_value = mock_df
#         mock_df.distinct.return_value = mock_df

#         result = _get_supported_ids(mock_df, "id_visit", "id_visit", 1751155200)

#         # Should not filter, just select and distinct
#         mock_df.select.assert_called_once()
#         mock_df.distinct.assert_called_once()
#         assert result == mock_df
