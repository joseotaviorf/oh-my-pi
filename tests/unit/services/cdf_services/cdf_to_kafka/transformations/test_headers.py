from datetime import datetime

import pytest
from pyspark.sql import functions as F

from bietlejuice.services.cdf_services.cdf_to_kafka.transformations.headers import (
    create_kafka_headers,
    get_data_columns_from,
)


@pytest.fixture
def sample_cdf_dataframe(spark_session):
    """Create a sample CDF DataFrame with test data."""
    data = [
        (
            1,
            "Alice",
            "alice@example.com",
            datetime.now(),
            "insert",
            12345,
            "2024-01-01T10:00:00Z",
        ),
        (
            2,
            "Bob",
            "bob@example.com",
            datetime.now(),
            "update",
            12346,
            "2024-01-01T10:01:00Z",
        ),
    ]

    schema = [
        "id",
        "name",
        "email",
        "created_at",
        "_change_type",
        "_commit_version",
        "_commit_timestamp",
    ]

    return spark_session.createDataFrame(data, schema)


class TestGetDataColumnsFrom:
    """Unit tests for get_data_columns_from function."""

    def test_get_data_columns_with_cdf_metadata(self, sample_cdf_dataframe):
        """Test extracting data columns when CDF metadata columns are present."""
        data_columns = get_data_columns_from(sample_cdf_dataframe)

        expected_columns = ["id", "name", "email", "created_at"]
        assert data_columns == expected_columns


class TestCreateKafkaHeaders:
    """Unit tests for create_kafka_headers function."""

    def test_headers_with_cdf_metadata_and_schema_id(self, sample_cdf_dataframe):
        """Test creating headers with CDF metadata and schema_id."""
        source_table = "test_db.test_table"
        entity = "test_entity"
        schema_id = 12345

        headers = create_kafka_headers(
            sample_cdf_dataframe, source_table, entity, schema_id
        )

        assert len(headers) == 7  # 3 CDF + 3 standard + 1 schema_id

        # Create a test DataFrame to collect actual header values
        test_df = sample_cdf_dataframe.limit(1)
        headers_col = F.array(*headers).alias("headers")
        result_df = test_df.select(headers_col)
        result = result_df.collect()[0]

        header_dict = {h["key"]: h["value"] for h in result["headers"]}

        # CDF metadata headers
        assert "_change_type" in header_dict
        assert "_commit_version" in header_dict
        assert "_commit_timestamp" in header_dict

        # Standard headers
        assert header_dict["source_table"].decode("utf-8") == source_table
        assert header_dict["feature_set_name"].decode("utf-8") == "test_table"
        assert header_dict["entity"].decode("utf-8") == entity

        # Schema ID header
        assert header_dict["schema_id"].decode("utf-8") == str(schema_id)

    def test_headers_without_schema_id(self, sample_cdf_dataframe):
        """Test creating headers without schema_id (plain JSON mode)."""
        source_table = "test_db.test_table"
        entity = "test_entity"

        headers = create_kafka_headers(sample_cdf_dataframe, source_table, entity)

        assert len(headers) == 6  # 3 CDF + 3 standard (no schema_id)

        # Create a test DataFrame to collect actual header values
        test_df = sample_cdf_dataframe.limit(1)
        headers_col = F.array(*headers).alias("headers")
        result_df = test_df.select(headers_col)
        result = result_df.collect()[0]

        header_dict = {h["key"]: h["value"] for h in result["headers"]}

        # Should not have schema_id header
        assert "schema_id" not in header_dict

        # Should have all other headers
        assert "_change_type" in header_dict
        assert "source_table" in header_dict
        assert "feature_set_name" in header_dict
        assert "entity" in header_dict

    def test_feature_set_name_extraction(self, sample_cdf_dataframe):
        """Test that feature_set_name is correctly extracted from source_table."""
        test_cases = [
            ("db.table", "table"),
            ("database.schema.table", "table"),
            ("db.table__latest", "table"),
            ("complex.db.schema.table__latest", "table"),
            ("single_table", "single_table"),
        ]

        entity = "test_entity"

        for source_table, expected_feature_set in test_cases:
            headers = create_kafka_headers(sample_cdf_dataframe, source_table, entity)

            # Create a test DataFrame to collect actual header values
            test_df = sample_cdf_dataframe.limit(1)
            headers_col = F.array(*headers).alias("headers")
            result_df = test_df.select(headers_col)
            result = result_df.collect()[0]

            header_dict = {h["key"]: h["value"] for h in result["headers"]}

            assert (
                header_dict["feature_set_name"].decode("utf-8") == expected_feature_set
            ), f"Failed for source_table: {source_table}"

    def test_header_values_are_binary(self, sample_cdf_dataframe):
        """Test that all header values are properly encoded as binary."""
        source_table = "test_db.test_table"
        entity = "test_entity"
        schema_id = 12345

        headers = create_kafka_headers(
            sample_cdf_dataframe, source_table, entity, schema_id
        )

        # Create a test DataFrame to collect actual header values
        test_df = sample_cdf_dataframe.limit(1)
        headers_col = F.array(*headers).alias("headers")
        result_df = test_df.select(headers_col)
        result = result_df.collect()[0]

        for header in result["headers"]:
            # Verify key format
            assert isinstance(
                header["key"], str
            ), f"Header key {header['key']} is not a string"
            assert header["key"], "Header key cannot be empty"

            # Verify value format
            assert isinstance(
                header["value"], bytearray
            ), f"Header {header['key']} value is not binary (bytearray)"
            assert (
                len(header["value"]) > 0
            ), f"Header {header['key']} value cannot be empty"
