"""Unit tests for CDF transformation utility functions.

This module tests simple transformation functions. Complex format transformations
are tested in dedicated modules:
- test_cdf_wire_format_transformations.py
- test_cdf_plain_json_transformations.py
- test_cdf_to_kafka_format.py
"""

from bietlejuice.services.cdf_services.cdf_transformations import (
    drop_partition_columns,
    filter_cdf_events,
)


class TestFilterCdfEvents:
    """Unit tests for filter_cdf_events function."""

    def test_keeps_insert_and_update_postimage_events(self, spark_session):
        """Test that only insert and update_postimage events are kept."""
        data = [
            (1, "Alice", "insert"),
            (2, "Bob", "update_preimage"),
            (2, "Bob Updated", "update_postimage"),
            (3, "Charlie", "delete"),
            (4, "David", "insert"),
        ]
        schema = "id INT, name STRING, _change_type STRING"
        df = spark_session.createDataFrame(data, schema)

        result = filter_cdf_events(df)
        rows = result.collect()

        assert len(rows) == 3
        change_types = [row._change_type for row in rows]
        assert set(change_types) == {"insert", "update_postimage"}

        result_ids = [row.id for row in rows]
        assert result_ids == [1, 2, 4]

    def test_filters_out_all_disallowed_types(self, spark_session):
        """Test that all disallowed types (preimage, delete) are filtered out."""
        data = [
            (1, "Name1", "update_preimage"),
            (2, "Name2", "delete"),
        ]
        schema = "id INT, name STRING, _change_type STRING"
        df = spark_session.createDataFrame(data, schema)

        result = filter_cdf_events(df)

        assert result.count() == 0


class TestDropPartitionColumns:
    """Unit tests for drop_partition_columns function."""

    def test_drops_all_partition_columns_when_present(self, spark_session):
        """Test that all partition columns (year, month, day) are dropped."""
        data = [
            (1, "Alice", "alice@example.com", 2024, 10, 16),
            (2, "Bob", "bob@example.com", 2024, 10, 16),
        ]
        columns = ["id", "name", "email", "year", "month", "day"]
        df = spark_session.createDataFrame(data, columns)

        result = drop_partition_columns(df)

        assert sorted(result.columns) == ["email", "id", "name"]
        assert result.count() == 2

    def test_handles_dataframe_without_partition_columns(self, spark_session):
        """Test that DataFrame without partition columns is unchanged."""
        data = [(1, "Alice", "alice@example.com"), (2, "Bob", "bob@example.com")]
        columns = ["id", "name", "email"]
        df = spark_session.createDataFrame(data, columns)

        result = drop_partition_columns(df)

        assert sorted(result.columns) == sorted(columns)
        assert result.count() == 2

    def test_drops_only_existing_partition_columns(self, spark_session):
        """Test that only present partition columns are dropped."""
        data = [
            (1, "Alice", "alice@example.com", 2024),
            (2, "Bob", "bob@example.com", 2024),
        ]
        columns = ["id", "name", "email", "year"]
        df = spark_session.createDataFrame(data, columns)

        result = drop_partition_columns(df)

        assert sorted(result.columns) == ["email", "id", "name"]
        assert result.count() == 2
