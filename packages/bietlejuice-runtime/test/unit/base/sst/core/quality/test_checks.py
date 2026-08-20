import pytest
from pyspark.sql.types import StringType, StructField, StructType

from bietlejuice.base.sst.core.quality.checks import validate_non_nullable_columns


class TestValidateNonNullableColumns:
    """Test cases for validate_non_nullable_columns."""

    def test_passes_when_non_nullable_columns_have_no_nulls(self, spark_session):
        # Arrange
        schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        df = spark_session.createDataFrame([("1", None), ("2", "Jane")], schema)
        column_schema = {
            "id": {"type": "string", "is_nullable": False},
            "name": {"type": "string", "is_nullable": True},  # nulls allowed
        }

        # Act
        null_counts = validate_non_nullable_columns(df, column_schema)

        # Assert
        assert null_counts == {}

    def test_fails_when_non_nullable_column_contains_nulls(self, spark_session):
        # Arrange
        schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        df = spark_session.createDataFrame(
            [("1", "John"), (None, "Jane"), (None, None)], schema
        )
        column_schema = {
            "id": {"type": "string", "is_nullable": False},
            "name": {"type": "string", "is_nullable": True},
        }

        # Act & Assert
        with pytest.raises(ValueError) as exc_info:
            validate_non_nullable_columns(df, column_schema)

        error_message = str(exc_info.value)
        assert "Null values found in non-nullable columns" in error_message
        assert "'id': 2" in error_message
        assert "'name'" not in error_message

    def test_returns_report_instead_of_raising_when_fail_false(self, spark_session):
        # Arrange
        schema = StructType([StructField("id", StringType(), True)])
        df = spark_session.createDataFrame([("1",), (None,)], schema)
        column_schema = {"id": {"type": "string", "is_nullable": False}}

        # Act
        null_counts = validate_non_nullable_columns(df, column_schema, fail=False)

        # Assert
        assert null_counts == {"id": 1}

    def test_omitted_is_nullable_allows_nulls(self, spark_session):
        # Arrange
        schema = StructType([StructField("id", StringType(), True)])
        df = spark_session.createDataFrame([("1",), (None,)], schema)
        column_schema = {"id": {"type": "string"}}

        # Act
        null_counts = validate_non_nullable_columns(df, column_schema)

        # Assert
        assert null_counts == {}

    def test_skips_columns_absent_from_dataframe(self, spark_session):
        # Arrange
        schema = StructType([StructField("id", StringType(), True)])
        df = spark_session.createDataFrame([("1",)], schema)
        column_schema = {
            "id": {"type": "string", "is_nullable": False},
            "missing": {"type": "string", "is_nullable": False},
        }

        # Act
        null_counts = validate_non_nullable_columns(df, column_schema)

        # Assert
        assert null_counts == {}

    def test_passes_on_empty_dataframe(self, spark_session):
        # Arrange
        schema = StructType([StructField("id", StringType(), True)])
        df = spark_session.createDataFrame([], schema)
        column_schema = {"id": {"type": "string", "is_nullable": False}}

        # Act
        null_counts = validate_non_nullable_columns(df, column_schema)

        # Assert
        assert null_counts == {}
