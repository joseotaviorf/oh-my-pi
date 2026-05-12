"""
Unit tests for data quality functions.
"""

import pytest
from pyspark.sql import functions as F

from bietlejuice.qube.jobs.common.data_quality import (
    DataQualityMetrics,
    log_processing_stats,
    validate_output,
    validate_source_data,
)


class TestDataQualityMetrics:
    """Tests for DataQualityMetrics class."""

    def test_data_quality_metrics_init(self):
        """Test DataQualityMetrics initialization."""
        metrics = DataQualityMetrics(
            row_count=100,
            null_counts={"col1": 5},
            distinct_counts={"col1": 10},
            warnings=["Warning 1"],
        )

        assert metrics.row_count == 100
        assert metrics.null_counts == {"col1": 5}
        assert metrics.distinct_counts == {"col1": 10}
        assert metrics.warnings == ["Warning 1"]

    def test_data_quality_metrics_to_dict(self):
        """Test DataQualityMetrics.to_dict()."""
        metrics = DataQualityMetrics(
            row_count=100,
            null_counts={"col1": 5},
            distinct_counts={"col1": 10},
            warnings=["Warning 1"],
        )

        result = metrics.to_dict()

        assert result["row_count"] == 100
        assert result["null_counts"] == {"col1": 5}
        assert result["distinct_counts"] == {"col1": 10}
        assert result["warnings"] == ["Warning 1"]


class TestValidateOutput:
    """Tests for validate_output function."""

    def test_validate_output_empty(self, spark):
        """Test validation of empty DataFrame."""
        df = spark.createDataFrame([], "id_visit string, date string, value string")

        metrics = validate_output(df, "visit", "status", 7, warn_empty=True)

        assert metrics.row_count == 0
        assert len(metrics.warnings) > 0
        assert "Empty output" in metrics.warnings[0]

    def test_validate_output_with_data(self, spark):
        """Test validation of DataFrame with data."""
        data = [
            ("v1", "2025-06-29", "value1"),
            ("v2", "2025-06-29", "value2"),
        ]
        df = spark.createDataFrame(data, ["id_visit", "date", "value"])

        metrics = validate_output(df, "visit", "status", 7)

        assert metrics.row_count == 2
        assert len(metrics.warnings) == 0

    def test_validate_output_high_null_rate(self, spark):
        """Test validation with high null rate."""
        data = [
            ("v1", "2025-06-29", None),
            ("v2", "2025-06-29", None),
            ("v3", "2025-06-29", "value"),
        ]
        df = spark.createDataFrame(data, ["id_visit", "date", "value"])

        metrics = validate_output(df, "visit", "status", 7, null_threshold=0.5)

        # 2/3 nulls = 66% > 50% threshold
        assert len(metrics.warnings) > 0
        assert "High null rate" in metrics.warnings[0]

    def test_validate_output_low_null_rate(self, spark):
        """Test validation with low null rate (no warning)."""
        data = [
            ("v1", "2025-06-29", "value1"),
            ("v2", "2025-06-29", None),
            ("v3", "2025-06-29", "value3"),
        ]
        df = spark.createDataFrame(data, ["id_visit", "date", "value"])

        metrics = validate_output(df, "visit", "status", 7, null_threshold=0.5)

        # 1/3 nulls = 33% < 50% threshold, but null_count > 0
        assert metrics.null_counts["value"] == 1

    def test_validate_output_distinct_counts(self, spark):
        """Test that distinct counts are calculated."""
        data = [
            ("v1", "2025-06-29", "value1"),
            ("v2", "2025-06-29", "value1"),
            ("v3", "2025-06-29", "value2"),
        ]
        df = spark.createDataFrame(data, ["id_visit", "date", "value"])

        metrics = validate_output(df, "visit", "status", 7)

        # Should have distinct count for id_visit (3 distinct)
        assert "id_visit" in metrics.distinct_counts
        assert metrics.distinct_counts["id_visit"] == 3

    def test_validate_output_no_warn_empty(self, spark):
        """Test validation with warn_empty=False."""
        df = spark.createDataFrame([], "id_visit string, date string")

        metrics = validate_output(df, "visit", "status", 7, warn_empty=False)

        assert metrics.row_count == 0
        # Should not have empty warning
        assert not any("Empty output" in w for w in metrics.warnings)

    def test_validate_output_no_check_nulls(self, spark):
        """Test validation with check_nulls=False."""
        from pyspark.sql.types import StringType, StructField, StructType

        schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("date", StringType(), True),
                StructField("value", StringType(), True),
            ]
        )
        data = [
            ("v1", "2025-06-29", None),
            ("v2", "2025-06-29", None),
        ]
        df = spark.createDataFrame(data, schema)

        metrics = validate_output(df, "visit", "status", 7, check_nulls=False)

        # Should still count nulls but not warn
        assert metrics.null_counts["value"] == 2
        assert not any("High null rate" in w for w in metrics.warnings)


class TestValidateSourceData:
    """Tests for validate_source_data function."""

    def test_validate_source_data_success(self, spark):
        """Test successful source data validation."""
        data = [
            ("v1", "2025-06-29", "RENT"),
            ("v2", "2025-06-28", "SALE"),
        ]
        df = spark.createDataFrame(data, ["id_visit", "dt_visit", "business_context"])

        # Should not raise
        validate_source_data(df, "visit", ["id_visit", "dt_visit", "business_context"])

    def test_validate_source_data_empty(self, spark):
        """Test validation fails on empty DataFrame."""
        df = spark.createDataFrame([], "id_visit string")

        with pytest.raises(ValueError, match="Source data is empty"):
            validate_source_data(df, "visit", ["id_visit"])

    def test_validate_source_data_missing_columns(self, spark):
        """Test validation fails on missing required columns."""
        data = [("v1", "2025-06-29")]
        df = spark.createDataFrame(data, ["id_visit", "dt_visit"])

        with pytest.raises(ValueError, match="Missing required columns"):
            validate_source_data(df, "visit", ["id_visit", "dt_visit", "missing_col"])

    def test_validate_source_data_with_date_col(self, spark):
        """Test validation with date column check."""
        data = [
            ("v1", "2025-06-25", "RENT"),
            ("v2", "2025-06-29", "SALE"),
        ]
        df = spark.createDataFrame(data, ["id_visit", "dt_visit", "business_context"])
        df = df.withColumn("dt_visit", F.to_date(F.col("dt_visit")))

        # Should not raise
        validate_source_data(df, "visit", ["id_visit", "dt_visit"], date_col="dt_visit")


class TestLogProcessingStats:
    """Tests for log_processing_stats function."""

    def test_log_processing_stats_with_reduction(self):
        """Test logging stats with input > output."""
        # This is mainly a smoke test - actual logging is hard to test
        # Just ensure it doesn't raise
        log_processing_stats(
            input_count=100,
            output_count=50,
            entity="visit",
            name="status",
            window_days=7,
        )

    def test_log_processing_stats_zero_input(self):
        """Test logging stats with zero input."""
        log_processing_stats(
            input_count=0, output_count=0, entity="visit", name="status", window_days=7
        )

    def test_log_processing_stats_no_reduction(self):
        """Test logging stats with input == output."""
        log_processing_stats(
            input_count=100,
            output_count=100,
            entity="visit",
            name="status",
            window_days=7,
        )
