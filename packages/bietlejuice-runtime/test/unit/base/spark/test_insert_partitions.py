"""
Unit tests for insert_partitions standalone function.

Uses mocks to avoid Spark session/pickle issues in Python 3.12 + PySpark 3.3.2.
"""

from unittest.mock import MagicMock

import pytest


class TestInsertPartitions:
    """Test suite for insert_partitions standalone function."""

    def test_returns_none_when_df_is_none(self):
        """Test that None is returned when input DataFrame is None."""
        from bietlejuice.base.spark.spark_dataframe_service import insert_partitions

        result = insert_partitions(None)
        assert result is None

    def test_adds_ts_load_and_partition_columns_without_date_column(self):
        """Test that ts_load, year, month, day are added when no date column specified."""
        from bietlejuice.base.spark.spark_dataframe_service import insert_partitions

        def make_chained_mock(columns):
            m = MagicMock()
            m.columns = columns
            m.withColumn.return_value = m
            m.where.return_value.count.return_value = 0
            m.count.return_value = 1
            return m

        mock_df = make_chained_mock(["a"])

        result = insert_partitions(mock_df)

        assert result is not None
        assert mock_df.withColumn.call_count >= 4  # ts_load, year, month, day

    def test_uses_date_column_when_present(self):
        """Test that date_column_to_partition is used when it exists in DataFrame."""
        from bietlejuice.base.spark.spark_dataframe_service import insert_partitions

        def make_chained_mock(columns):
            m = MagicMock()
            m.columns = columns
            m.withColumn.return_value = m
            m.where.return_value.count.return_value = 0
            m.count.return_value = 1
            return m

        mock_df = make_chained_mock(["event_date"])

        result = insert_partitions(mock_df, date_column_to_partition="event_date")

        assert result is not None
        mock_df.withColumn.assert_called()

    def test_uses_ts_load_fallback_when_date_column_not_found(self):
        """Test that ts_load is used when specified date column does not exist."""
        from bietlejuice.base.spark.spark_dataframe_service import insert_partitions

        def make_chained_mock(columns):
            m = MagicMock()
            m.columns = columns
            m.withColumn.return_value = m
            return m

        mock_df = make_chained_mock(["a"])

        result = insert_partitions(
            mock_df, date_column_to_partition="nonexistent_column"
        )

        assert result is not None

    def test_accepts_datetime_format_parameter(self):
        """Test that datetime_format parameter is accepted and does not raise."""
        from bietlejuice.base.spark.spark_dataframe_service import insert_partitions

        def make_chained_mock(columns):
            m = MagicMock()
            m.columns = columns
            m.withColumn.return_value = m
            m.where.return_value.count.return_value = 0
            m.count.return_value = 1
            return m

        mock_df = make_chained_mock(["ts"])

        result = insert_partitions(
            mock_df,
            date_column_to_partition="ts",
            datetime_format="dd/MM/yyyy HH:mm:ss",
        )

        assert result is not None

    def test_raises_when_all_partitions_null(self):
        """Test that ValueError is raised when all date conversions fail."""
        from bietlejuice.base.spark.spark_dataframe_service import insert_partitions

        def make_chained_mock(columns, null_count=0, total_count=1):
            m = MagicMock()
            m.columns = columns
            m.withColumn.return_value = m
            m.where.return_value.count.return_value = null_count
            m.count.return_value = total_count
            return m

        mock_df = make_chained_mock(["invalid_date"], null_count=2, total_count=2)

        with pytest.raises(ValueError) as exc_info:
            insert_partitions(mock_df, date_column_to_partition="invalid_date")

        assert "all date conversions failed" in str(exc_info.value).lower()
