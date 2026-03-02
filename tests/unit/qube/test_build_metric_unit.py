"""Unit tests for build_metric.py refactored functions."""

import unittest
from unittest.mock import MagicMock, patch

from bietlejuice.qube.jobs.metrics.build_metric import (
    MetricConfig,
    _setup_configuration,
    _extract_metric_config,
    _identify_entity_id_column,
    _determine_use_approx_counter,
    _build_measure_aggregation,
)


class TestMetricConfigDataclass(unittest.TestCase):
    """Test MetricConfig dataclass."""

    def test_metric_config_creation(self):
        """Test MetricConfig can be created with all fields."""
        config = MetricConfig(
            entity="visit",
            name="conversions",
            windows=[1, 7, 28],
            dim_specs=[{"name": "status", "card": "single", "type": "string"}],
            meas_specs=[{"name": "purchased", "filter": "status = 'completed'"}],
            k_anonymity=10,
            counter_type="long",
        )

        self.assertEqual(config.entity, "visit")
        self.assertEqual(config.name, "conversions")
        self.assertEqual(config.windows, [1, 7, 28])
        self.assertEqual(len(config.dim_specs), 1)
        self.assertEqual(len(config.meas_specs), 1)
        self.assertEqual(config.k_anonymity, 10)
        self.assertEqual(config.counter_type, "long")

    def test_metric_config_approx_counter(self):
        """Test MetricConfig with approx counter type."""
        config = MetricConfig(
            entity="user",
            name="engagement",
            windows=[7],
            dim_specs=[],
            meas_specs=[],
            k_anonymity=5,
            counter_type="approx",
        )

        self.assertEqual(config.counter_type, "approx")


class TestSetupConfiguration(unittest.TestCase):
    """Test _setup_configuration function."""

    def test_setup_configuration(self):
        """Test configuration setup from args."""
        args = MagicMock()
        args.env = "dev"
        args.config_root = "/path/to/config"
        args.db_prefix = "test_prefix"
        args.warehouse = "/warehouse"

        conf = _setup_configuration(args)

        self.assertEqual(conf.env, "dev")
        self.assertEqual(conf.config_root, "/path/to/config")
        self.assertEqual(conf.db_prefix, "test_prefix")
        self.assertEqual(conf.warehouse_path, "/warehouse")


class TestExtractMetricConfig(unittest.TestCase):
    """Test _extract_metric_config function."""

    def test_extract_metric_config_basic(self):
        """Test extracting basic metric configuration."""
        spec = {
            "entity": "visit",
            "name": "conversions",
            "windows": [1, 7, 28],
            "dimensions": [{"name": "status", "card": "single", "type": "string"}],
            "measures": [{"name": "purchased"}],
            "privacy": {"k_anonymity": 15},
            "counters": {"type": "long"},
        }
        conf = MagicMock()

        metric_config = _extract_metric_config(spec, conf)

        self.assertEqual(metric_config.entity, "visit")
        self.assertEqual(metric_config.name, "conversions")
        self.assertEqual(metric_config.windows, [1, 7, 28])
        self.assertEqual(len(metric_config.dim_specs), 1)
        self.assertEqual(len(metric_config.meas_specs), 1)
        self.assertEqual(metric_config.k_anonymity, 15)
        self.assertEqual(metric_config.counter_type, "long")

    def test_extract_metric_config_single_window(self):
        """Test extracting config with single window (not a list)."""
        spec = {
            "entity": "user",
            "name": "activity",
            "windows": 7,  # Single value, not a list
            "dimensions": [],
            "measures": [],
        }
        conf = MagicMock()

        metric_config = _extract_metric_config(spec, conf)

        self.assertEqual(metric_config.windows, [7])

    def test_extract_metric_config_defaults(self):
        """Test extracting config with default values."""
        spec = {"entity": "visit", "name": "metrics"}
        conf = MagicMock()

        metric_config = _extract_metric_config(spec, conf)

        self.assertEqual(metric_config.windows, [1, 7, 28])
        self.assertEqual(metric_config.dim_specs, [])
        self.assertEqual(metric_config.meas_specs, [])
        self.assertEqual(metric_config.k_anonymity, 10)
        self.assertEqual(metric_config.counter_type, "long")

    def test_extract_metric_config_approx_counter(self):
        """Test extracting config with approx counter type."""
        spec = {"entity": "visit", "name": "metrics", "counters": {"type": "approx"}}
        conf = MagicMock()

        metric_config = _extract_metric_config(spec, conf)

        self.assertEqual(metric_config.counter_type, "approx")


class TestIdentifyEntityIdColumn(unittest.TestCase):
    """Test _identify_entity_id_column function."""

    def test_identify_entity_id_column_visit(self):
        """Test identifying visit_id column."""
        df = MagicMock()
        df.columns = ["date", "visit_id", "value"]

        entity_id_col = _identify_entity_id_column(df)

        self.assertEqual(entity_id_col, "visit_id")

    def test_identify_entity_id_column_user(self):
        """Test identifying user_id column."""
        df = MagicMock()
        df.columns = ["date", "user_id", "value"]

        entity_id_col = _identify_entity_id_column(df)

        self.assertEqual(entity_id_col, "user_id")

    def test_identify_entity_id_column_multiple(self):
        """Test identifying first entity column when multiple exist."""
        df = MagicMock()
        df.columns = ["date", "visit_id", "session_id", "value"]

        entity_id_col = _identify_entity_id_column(df)

        self.assertEqual(entity_id_col, "visit_id")

    def test_identify_entity_id_column_not_found(self):
        """Test error when entity_id column not found."""
        df = MagicMock()
        df.columns = ["date", "value"]

        with self.assertRaises(ValueError) as context:
            _identify_entity_id_column(df)

        self.assertIn("Could not identify entity_id column", str(context.exception))


class TestDetermineUseApproxCounter(unittest.TestCase):
    """Test _determine_use_approx_counter function."""

    def test_use_approx_with_multi(self):
        """Test uses approx counter when has_multi is True."""
        result = _determine_use_approx_counter(has_multi=True, counter_type="long")
        self.assertTrue(result)

    def test_use_approx_with_approx_type(self):
        """Test uses approx counter when counter_type is approx."""
        result = _determine_use_approx_counter(has_multi=False, counter_type="approx")
        self.assertTrue(result)

    def test_use_approx_with_both(self):
        """Test uses approx counter when both conditions are true."""
        result = _determine_use_approx_counter(has_multi=True, counter_type="approx")
        self.assertTrue(result)

    def test_use_exact_counter(self):
        """Test uses exact counter when both conditions are false."""
        result = _determine_use_approx_counter(has_multi=False, counter_type="long")
        self.assertFalse(result)


class TestBuildMeasureAggregation(unittest.TestCase):
    """Test _build_measure_aggregation function."""

    @patch("bietlejuice.qube.jobs.metrics.build_metric._determine_use_approx_counter")
    @patch("bietlejuice.qube.jobs.metrics.build_metric.F.col")
    @patch("bietlejuice.qube.jobs.metrics.build_metric.F.when")
    @patch("bietlejuice.qube.jobs.metrics.build_metric.F.countDistinct")
    def test_build_measure_aggregation_exact(
        self, mock_count_distinct, mock_when, mock_col, mock_determine
    ):
        """Test building exact count aggregation."""
        mock_determine.return_value = False
        mock_col_obj = MagicMock()
        mock_col.return_value = mock_col_obj
        mock_when_obj = MagicMock()
        mock_when.return_value = mock_when_obj
        mock_expr = MagicMock()
        mock_count_distinct.return_value.alias.return_value = mock_expr

        expr, out_col = _build_measure_aggregation(
            "purchased", "visit_id", False, 7, "long"
        )

        self.assertEqual(out_col, "measure_purchased_7d_counter")
        mock_col.assert_any_call("m_purchased")
        mock_col.assert_any_call("visit_id")
        mock_when.assert_called_once()
        mock_count_distinct.assert_called_once()

    @patch("bietlejuice.qube.jobs.metrics.build_metric._determine_use_approx_counter")
    @patch("bietlejuice.qube.jobs.metrics.build_metric.F.col")
    @patch("bietlejuice.qube.jobs.metrics.build_metric.F.when")
    @patch("bietlejuice.qube.jobs.metrics.build_metric.F.approx_count_distinct")
    def test_build_measure_aggregation_approx(
        self, mock_approx_count, mock_when, mock_col, mock_determine
    ):
        """Test building approx count aggregation."""
        mock_determine.return_value = True
        mock_col_obj = MagicMock()
        mock_col.return_value = mock_col_obj
        mock_when_obj = MagicMock()
        mock_when.return_value = mock_when_obj
        mock_expr = MagicMock()
        mock_approx_count.return_value.alias.return_value = mock_expr

        expr, out_col = _build_measure_aggregation(
            "purchased", "visit_id", True, 28, "approx"
        )

        self.assertEqual(out_col, "measure_purchased_28d_counter_approx")
        mock_col.assert_any_call("m_purchased")
        mock_col.assert_any_call("visit_id")
        mock_when.assert_called_once()
        mock_approx_count.assert_called_once()

    @patch("bietlejuice.qube.jobs.metrics.build_metric._determine_use_approx_counter")
    @patch("bietlejuice.qube.jobs.metrics.build_metric.F.col")
    @patch("bietlejuice.qube.jobs.metrics.build_metric.F.when")
    @patch("bietlejuice.qube.jobs.metrics.build_metric.F.approx_count_distinct")
    def test_build_measure_aggregation_multi_valued(
        self, mock_approx_count, mock_when, mock_col, mock_determine
    ):
        """Test building aggregation for multi-valued dimension (uses approx)."""
        mock_determine.return_value = True
        mock_col_obj = MagicMock()
        mock_col.return_value = mock_col_obj
        mock_when_obj = MagicMock()
        mock_when.return_value = mock_when_obj
        mock_expr = MagicMock()
        mock_approx_count.return_value.alias.return_value = mock_expr

        expr, out_col = _build_measure_aggregation(
            "converted", "user_id", True, 1, "long"
        )

        self.assertEqual(out_col, "measure_converted_1d_counter_approx")
        mock_determine.assert_called_once_with(True, "long")


class TestBuildAggExprs(unittest.TestCase):
    """Test _build_agg_exprs function."""

    @patch("bietlejuice.qube.jobs.metrics.build_metric._build_measure_aggregation")
    def test_build_agg_exprs_single_measure(self, mock_build_agg):
        """Test building aggregation expressions for single measure."""
        from bietlejuice.qube.jobs.metrics.build_metric import _build_agg_exprs

        meas_specs = [{"name": "purchased"}]
        mock_expr = MagicMock()
        mock_build_agg.return_value = (mock_expr, "measure_purchased_7d_counter")
        measure_output_cols = []

        result = _build_agg_exprs(
            meas_specs, "visit_id", False, 7, "long", measure_output_cols
        )

        self.assertEqual(len(result), 1)
        self.assertEqual(len(measure_output_cols), 1)
        self.assertEqual(measure_output_cols[0], "measure_purchased_7d_counter")
        mock_build_agg.assert_called_once_with(
            "purchased", "visit_id", False, 7, "long"
        )

    @patch("bietlejuice.qube.jobs.metrics.build_metric._build_measure_aggregation")
    def test_build_agg_exprs_multiple_measures(self, mock_build_agg):
        """Test building aggregation expressions for multiple measures."""
        from bietlejuice.qube.jobs.metrics.build_metric import _build_agg_exprs

        meas_specs = [{"name": "purchased"}, {"name": "viewed"}, {"name": "clicked"}]
        mock_build_agg.side_effect = [
            (MagicMock(), "measure_purchased_28d_counter"),
            (MagicMock(), "measure_viewed_28d_counter"),
            (MagicMock(), "measure_clicked_28d_counter"),
        ]
        measure_output_cols = []

        result = _build_agg_exprs(
            meas_specs, "user_id", False, 28, "long", measure_output_cols
        )

        self.assertEqual(len(result), 3)
        self.assertEqual(len(measure_output_cols), 3)
        self.assertIn("measure_purchased_28d_counter", measure_output_cols)
        self.assertIn("measure_viewed_28d_counter", measure_output_cols)
        self.assertIn("measure_clicked_28d_counter", measure_output_cols)


class TestLoadSpec(unittest.TestCase):
    """Test _load_spec function."""

    @patch("bietlejuice.qube.jobs.metrics.build_metric.validate_spec_path")
    @patch("bietlejuice.qube.jobs.metrics.build_metric.load_spec")
    def test_load_spec_from_file(self, mock_load_spec, mock_validate_path):
        """Test loading spec from file."""
        from bietlejuice.qube.jobs.metrics.build_metric import _load_spec
        from pathlib import Path

        args = MagicMock()
        args.spec = "/path/to/spec.yaml"
        args.spec_json = None

        mock_spec = {"entity": "visit", "name": "conversions"}
        mock_load_spec.return_value = mock_spec
        mock_validate_path.return_value = Path("/path/to/spec.yaml")

        result = _load_spec(args)

        self.assertEqual(result, mock_spec)
        mock_validate_path.assert_called_once_with(
            "/path/to/spec.yaml", must_exist=True
        )
        mock_load_spec.assert_called_once_with("/path/to/spec.yaml", validate=True)

    @patch("bietlejuice.qube.jobs.common.specs_loader.load_spec_from_json")
    def test_load_spec_from_json(self, mock_load_json):
        """Test loading spec from JSON string."""
        from bietlejuice.qube.jobs.metrics.build_metric import _load_spec

        args = MagicMock()
        args.spec = None
        args.spec_json = '{"entity": "visit", "name": "conversions"}'

        mock_spec = {"entity": "visit", "name": "conversions"}
        mock_load_json.return_value = mock_spec

        result = _load_spec(args)

        self.assertEqual(result, mock_spec)
        mock_load_json.assert_called_once_with(
            '{"entity": "visit", "name": "conversions"}', validate=True
        )


class TestAggregateMetrics(unittest.TestCase):
    """Test _aggregate_metrics function."""

    @patch("bietlejuice.qube.jobs.metrics.build_metric._build_agg_exprs")
    def test_aggregate_metrics(self, mock_build_agg_exprs):
        """Test aggregating metrics."""
        from bietlejuice.qube.jobs.metrics.build_metric import _aggregate_metrics

        df = MagicMock()
        mock_grouped = MagicMock()
        df.groupBy.return_value = mock_grouped
        mock_result = MagicMock()
        mock_result.count.return_value = 100
        mock_grouped.agg.return_value = mock_result

        dim_cols_info = [("dim_status", "string"), ("dim_device", "string")]
        meas_specs = [{"name": "purchased"}]
        mock_agg_exprs = [MagicMock()]
        mock_build_agg_exprs.return_value = mock_agg_exprs
        measure_output_cols = []

        result = _aggregate_metrics(
            df,
            dim_cols_info,
            meas_specs,
            "visit_id",
            False,
            7,
            "long",
            measure_output_cols,
        )

        df.groupBy.assert_called_once_with("date", "dim_status", "dim_device")
        mock_grouped.agg.assert_called_once_with(*mock_agg_exprs)
        mock_result.count.assert_called_once()
        self.assertEqual(result, mock_result)


class TestApplyPrivacyProtection(unittest.TestCase):
    """Test _apply_privacy_protection function."""

    @patch("bietlejuice.qube.jobs.metrics.build_metric.apply_k_anonymity")
    def test_apply_privacy_protection(self, mock_apply_k):
        """Test applying k-anonymity protection."""
        from bietlejuice.qube.jobs.metrics.build_metric import _apply_privacy_protection

        df = MagicMock()
        dim_cols_info = [("dim_status", "string")]
        measure_output_cols = ["measure_purchased_7d_counter"]
        mock_result = MagicMock()
        mock_apply_k.return_value = mock_result

        result = _apply_privacy_protection(df, dim_cols_info, measure_output_cols, 10)

        mock_apply_k.assert_called_once_with(df, dim_cols_info, measure_output_cols, 10)
        self.assertEqual(result, mock_result)

    @patch("bietlejuice.qube.jobs.metrics.build_metric.apply_k_anonymity")
    def test_apply_privacy_protection_custom_k(self, mock_apply_k):
        """Test applying k-anonymity with custom k value."""
        from bietlejuice.qube.jobs.metrics.build_metric import _apply_privacy_protection

        df = MagicMock()
        dim_cols_info = [("dim_status", "string")]
        measure_output_cols = ["measure_purchased_7d_counter"]
        mock_result = MagicMock()
        mock_apply_k.return_value = mock_result

        result = _apply_privacy_protection(  # pyright: ignore[reportUnusedVariable]
            df, dim_cols_info, measure_output_cols, 25
        )

        mock_apply_k.assert_called_once_with(df, dim_cols_info, measure_output_cols, 25)
        self.assertEqual(result, mock_result)


if __name__ == "__main__":
    unittest.main()
