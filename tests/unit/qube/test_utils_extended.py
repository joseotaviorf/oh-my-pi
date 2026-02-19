"""
Extended unit tests for utility functions.
"""

import pytest
from pyspark.sql import functions as F
from bietlejuice.qube.jobs.common.utils import (
    load_table,
    get_window_range,
    wrap_dimension_value,
    extract_dimension_value,
)


class TestLoadTable:
    """Tests for load_table function."""

    # def test_load_table_from_metastore(self, spark):
    #     """Test loading table from metastore."""
    #     # Create a test table
    #     spark.sql("CREATE DATABASE IF NOT EXISTS test_db")
    #     test_data = [("v1", "2025-06-29"), ("v2", "2025-06-28")]
    #     df = spark.createDataFrame(test_data, ["id_visit", "dt_visit"])
    #     df.write.mode("overwrite").saveAsTable("test_db.test_table")

    #     # Load it
    #     result = load_table(spark, "test_db.test_table", env="dev")

    #     assert result.count() == 2

    def test_load_table_not_found(self, spark):
        """Test loading non-existent table raises error."""
        with pytest.raises(Exception):
            load_table(spark, "nonexistent.table", env="dev")


class TestGetWindowRange:
    """Tests for get_window_range function."""

    def test_get_window_range_with_date_string(self):
        """Test get_window_range with date string."""
        lo, hi = get_window_range("2025-06-29", 7)

        assert hi > lo
        assert hi - lo == 7 * 86400

    # def test_get_window_range_with_table(self, spark):
    #     """Test get_window_range inferring from table."""
    #     # Create test table with date column
    #     test_data = [
    #         ("v1", 1751155200),  # 2025-06-29
    #         ("v2", 1751068800),  # 2025-06-28
    #     ]
    #     df = spark.createDataFrame(test_data, ["id_visit", "event_date"])
    #     df.write.mode("overwrite").saveAsTable("test_db.test_table")

    #     lo, hi = get_window_range(
    #         date_str=None,
    #         window_days=7,
    #         spark=spark,
    #         table_name="test_db.test_table",
    #         date_col="event_date",
    #         env="dev",
    #     )

    #     assert hi > lo
    #     assert hi - lo == 7 * 86400

    # def test_get_window_range_empty_table(self, spark):
    #     """Test get_window_range with empty table defaults to today."""
    #     # Create empty table
    #     df = spark.createDataFrame([], "id_visit string, event_date long")
    #     df.write.mode("overwrite").saveAsTable("test_db.empty_table")

    #     lo, hi = get_window_range(
    #         date_str=None,
    #         window_days=7,
    #         spark=spark,
    #         table_name="test_db.empty_table",
    #         date_col="event_date",
    #         env="dev",
    #     )

    #     # Should default to today, so hi should be recent
    #     from datetime import datetime

    #     today_ts = int(
    #         datetime.now()
    #         .replace(hour=0, minute=0, second=0, microsecond=0)
    #         .timestamp()
    #     )
    #     # Allow some tolerance
    #     assert abs(hi - today_ts) < 86400  # Within 1 day

    # def test_get_window_range_missing_params(self):
    #     """Test get_window_range without date_str requires spark/table."""
    #     with pytest.raises(
    #         ValueError, match="spark, table_name, and date_col must be provided"
    #     ):
    #         get_window_range(None, 7)


class TestWrapDimensionValue:
    """Tests for wrap_dimension_value function."""

    # def test_wrap_dimension_value_single_string(self, spark):
    #     """Test wrapping single string value."""
    #     df = spark.createDataFrame([("value1",)], ["col"])
    #     result = df.select(
    #         wrap_dimension_value("col", "single", "string").alias("wrapped")
    #     )

    #     row = result.collect()[0]
    #     import json

    #     parsed = json.loads(row["wrapped"])

    #     assert "singleValued" in parsed
    #     assert parsed["singleValued"]["stringValue"] == "value1"

    def test_wrap_dimension_value_single_number(self, spark):
        """Test wrapping single number value."""
        df = spark.createDataFrame([(123.45,)], ["col"])
        result = df.select(
            wrap_dimension_value("col", "single", "number").alias("wrapped")
        )

        row = result.collect()[0]
        import json

        parsed = json.loads(row["wrapped"])

        assert "singleValued" in parsed
        assert parsed["singleValued"]["numberValue"] == 123.45

    def test_wrap_dimension_value_single_boolean(self, spark):
        """Test wrapping single boolean value."""
        df = spark.createDataFrame([(True,)], ["col"])
        result = df.select(
            wrap_dimension_value("col", "single", "boolean").alias("wrapped")
        )

        row = result.collect()[0]
        import json

        parsed = json.loads(row["wrapped"])

        assert "singleValued" in parsed
        assert parsed["singleValued"]["booleanValue"] is True

    def test_wrap_dimension_value_invalid_type(self, spark):
        """Test wrapping with invalid type raises error."""
        df = spark.createDataFrame([("value",)], ["col"])

        with pytest.raises(ValueError, match="Unknown type"):
            df.select(
                wrap_dimension_value("col", "single", "invalid").alias("wrapped")
            ).collect()

    def test_wrap_dimension_value_invalid_card(self, spark):
        """Test wrapping with invalid cardinality raises error."""
        df = spark.createDataFrame([("value",)], ["col"])

        with pytest.raises(ValueError, match="Unknown cardinality"):
            df.select(
                wrap_dimension_value("col", "invalid", "string").alias("wrapped")
            ).collect()


class TestExtractDimensionValue:
    """Tests for extract_dimension_value function."""

    def test_extract_dimension_value_single_string(self, spark):
        """Test extracting single string value from JSON."""
        import json

        json_str = json.dumps({"singleValued": {"stringValue": "test_value"}})

        df = spark.createDataFrame([(json_str,)], ["json_col"])
        result = df.select(
            extract_dimension_value(F.col("json_col"), "single", "string").alias(
                "extracted"
            )
        )

        row = result.collect()[0]
        assert row["extracted"] == "test_value"

    def test_extract_dimension_value_single_number(self, spark):
        """Test extracting single number value from JSON."""
        import json

        json_str = json.dumps({"singleValued": {"numberValue": 123.45}})

        df = spark.createDataFrame([(json_str,)], ["json_col"])
        result = df.select(
            extract_dimension_value(F.col("json_col"), "single", "number").alias(
                "extracted"
            )
        )

        row = result.collect()[0]
        assert row["extracted"] == 123.45

    def test_extract_dimension_value_single_boolean(self, spark):
        """Test extracting single boolean value from JSON."""
        import json

        json_str = json.dumps({"singleValued": {"booleanValue": True}})

        df = spark.createDataFrame([(json_str,)], ["json_col"])
        result = df.select(
            extract_dimension_value(F.col("json_col"), "single", "boolean").alias(
                "extracted"
            )
        )

        row = result.collect()[0]
        assert row["extracted"] is True
