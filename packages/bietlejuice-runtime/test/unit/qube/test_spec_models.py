"""
Unit tests for Pydantic spec model validation.
"""

import pytest
from pydantic import ValidationError

from bietlejuice.qube.jobs.common.spec_models import (
    DimensionSpec,
    LogicSpec,
    MeasureSpec,
    MetricSpec,
    SourceSpec,
)


class TestLogicSpec:
    """Tests for LogicSpec validation."""

    def test_valid_logic_spec_minimal(self):
        """Test minimal valid logic spec."""
        spec = LogicSpec()
        assert spec.card == "single"
        assert spec.type == "string"
        assert spec.agg is None
        assert spec.value_col is None

    def test_valid_logic_spec_with_value_col(self):
        """Test logic spec with value_col."""
        spec = LogicSpec(card="single", type="string", agg="last", value_col="status")
        assert spec.value_col == "status"

    def test_invalid_card(self):
        """Test invalid cardinality raises error."""
        with pytest.raises(ValidationError):
            LogicSpec(card="invalid")

    def test_invalid_type(self):
        """Test invalid type raises error."""
        with pytest.raises(ValidationError):
            LogicSpec(type="invalid")

    def test_valid_multi_card(self):
        """Test multi cardinality is accepted."""
        spec = LogicSpec(card="multi", type="string")
        assert spec.card == "multi"


class TestSourceSpec:
    """Tests for SourceSpec validation."""

    def test_valid_source_spec(self):
        """Test valid source spec."""
        spec = SourceSpec(
            table="core.visit",
            entity_id_col="id_visit",
            date_expr="unix_timestamp(dt_visit, 'yyyy-MM-dd')",
        )
        assert spec.table == "core.visit"
        assert spec.entity_id_col == "id_visit"

    def test_missing_required_fields(self):
        """Test missing required fields raises error."""
        with pytest.raises(ValidationError):
            SourceSpec(table="core.visit")


class TestDimensionSpec:
    """Tests for DimensionSpec validation."""

    def test_valid_dimension_spec_minimal(self):
        """Test minimal valid dimension spec."""
        spec = DimensionSpec(
            entity="visit",
            name="status",
            source=SourceSpec(
                table="core.visit",
                entity_id_col="id_visit",
                date_expr="unix_timestamp(dt_visit)",
            ),
            logic=LogicSpec(card="single", type="string"),
        )
        assert spec.entity == "visit"
        assert spec.name == "status"
        assert spec.extra_cols == []
        assert spec.include_all_entities is False

    def test_dimension_spec_with_extra_cols(self):
        """Test dimension spec with extra_cols."""
        spec = DimensionSpec(
            entity="contract",
            name="status",
            source=SourceSpec(
                table="core.contract",
                entity_id_col="id_contract",
                date_expr="unix_timestamp(dt_started)",
            ),
            logic=LogicSpec(
                card="single", type="string", agg="last", value_col="status"
            ),
            extra_cols=["dt_started", "ts_updated"],
        )
        assert spec.extra_cols == ["dt_started", "ts_updated"]

    def test_dimension_spec_with_include_all_entities(self):
        """Test dimension spec with include_all_entities."""
        spec = DimensionSpec(
            entity="visit",
            name="status",
            source=SourceSpec(
                table="core.visit",
                entity_id_col="id_visit",
                date_expr="unix_timestamp(dt_visit)",
            ),
            logic=LogicSpec(),
            include_all_entities=True,
        )
        assert spec.include_all_entities is True

    def test_dimension_spec_windows_single(self):
        """Test single window value is converted to list."""
        spec = DimensionSpec(
            entity="visit",
            name="status",
            source=SourceSpec(
                table="core.visit",
                entity_id_col="id_visit",
                date_expr="unix_timestamp(dt_visit)",
            ),
            logic=LogicSpec(),
            windows=7,
        )
        assert spec.windows == [7]

    def test_dimension_spec_windows_list(self):
        """Test multiple windows."""
        spec = DimensionSpec(
            entity="visit",
            name="status",
            source=SourceSpec(
                table="core.visit",
                entity_id_col="id_visit",
                date_expr="unix_timestamp(dt_visit)",
            ),
            logic=LogicSpec(),
            windows=[1, 7, 28],
        )
        assert spec.windows == [1, 7, 28]

    def test_dimension_spec_invalid_windows(self):
        """Test invalid windows raises error."""
        with pytest.raises(ValidationError):
            DimensionSpec(
                entity="visit",
                name="status",
                source=SourceSpec(
                    table="core.visit",
                    entity_id_col="id_visit",
                    date_expr="unix_timestamp(dt_visit)",
                ),
                logic=LogicSpec(),
                windows=-1,
            )


class TestMeasureSpec:
    """Tests for MeasureSpec validation."""

    def test_valid_measure_spec(self):
        """Test valid measure spec."""
        spec = MeasureSpec(
            entity="visit",
            name="unique",
            source=SourceSpec(
                table="core.visit",
                entity_id_col="id_visit",
                date_expr="unix_timestamp(dt_visit)",
            ),
            logic=LogicSpec(filter_sql="TRUE"),
        )
        assert spec.entity == "visit"
        assert spec.name == "unique"

    def test_measure_spec_with_filter(self):
        """Test measure spec with filter_sql."""
        spec = MeasureSpec(
            entity="visit",
            name="rent",
            source=SourceSpec(
                table="core.visit",
                entity_id_col="id_visit",
                date_expr="unix_timestamp(dt_visit)",
            ),
            logic=LogicSpec(filter_sql="business_context = 'RENT'"),
        )
        assert spec.logic.filter_sql == "business_context = 'RENT'"


class TestMetricSpec:
    """Tests for MetricSpec validation."""

    def test_valid_metric_spec(self):
        """Test valid metric spec."""
        from bietlejuice.qube.jobs.common.spec_models import (
            MetricDimensionRef,
            MetricMeasureRef,
            PrivacySpec,
        )

        spec = MetricSpec(
            entity="visit",
            name="unique_rent",
            dimensions=[
                MetricDimensionRef(
                    name="business_context", card="single", type="string"
                ),
                MetricDimensionRef(name="status", card="single", type="string"),
            ],
            measures=[
                MetricMeasureRef(name="unique"),
                MetricMeasureRef(name="rent"),
            ],
            privacy=PrivacySpec(k_anonymity=10),
        )
        assert spec.entity == "visit"
        assert len(spec.dimensions) == 2
        assert len(spec.measures) == 2
        assert spec.privacy.k_anonymity == 10

    def test_metric_spec_privacy_none_by_default(self):
        """Test privacy is None by default."""
        from bietlejuice.qube.jobs.common.spec_models import (
            MetricDimensionRef,
            MetricMeasureRef,
        )

        spec = MetricSpec(
            entity="visit",
            name="test",
            dimensions=[MetricDimensionRef(name="d1")],
            measures=[MetricMeasureRef(name="m1")],
        )
        # Privacy is None by default if not specified
        assert spec.privacy is None

    def test_metric_spec_privacy_default_k(self):
        """Test default k-anonymity value when privacy is specified."""
        from bietlejuice.qube.jobs.common.spec_models import (
            MetricDimensionRef,
            MetricMeasureRef,
            PrivacySpec,
        )

        spec = MetricSpec(
            entity="visit",
            name="test",
            dimensions=[MetricDimensionRef(name="d1")],
            measures=[MetricMeasureRef(name="m1")],
            privacy=PrivacySpec(),  # Use default k value
        )
        assert spec.privacy.k_anonymity == 10
