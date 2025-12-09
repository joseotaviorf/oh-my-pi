import json
from datetime import datetime

import pytest
from pyspark.sql import SparkSession

from bietlejuice.services.cdf_services.cdf_plain_json_transformations import (
    cdf_to_kafka_format_plain_json,
)


@pytest.fixture
def spark_session():
    """Create a Spark session for testing."""
    return SparkSession.builder.appName("test_cdf_plain_json").getOrCreate()


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


class TestCdfToKafkaFormatPlainJson:
    """Unit tests for cdf_to_kafka_format_plain_json function."""

    def test_headers_content(self, sample_cdf_dataframe):
        """Test that headers contain expected CDF metadata, source table, and entity (no schema_id)."""
        source_table = "test_db.test_table"
        entity = "test_entity"

        result = cdf_to_kafka_format_plain_json(
            sample_cdf_dataframe,
            key_columns=["id"],
            source_table=source_table,
            entity=entity,
        )

        first_row = result.collect()[0]
        headers = first_row["headers"]

        header_dict = {h["key"]: h["value"] for h in headers}

        # CDF metadata headers
        assert "_change_type" in header_dict
        assert "_commit_version" in header_dict
        assert "_commit_timestamp" in header_dict

        # Standard headers
        assert header_dict["source_table"].decode("utf-8") == source_table
        assert header_dict["feature_set_name"].decode("utf-8") == "test_table"
        assert header_dict["entity"].decode("utf-8") == entity

        # Should NOT have schema_id header in plain JSON mode
        assert "schema_id" not in header_dict

    def test_key_column_content(self, sample_cdf_dataframe):
        """Test that key column contains the specified key columns as JSON."""
        result = cdf_to_kafka_format_plain_json(
            sample_cdf_dataframe,
            key_columns=["id"],
            source_table="test_db.test_table",
            entity="test_entity",
        )

        first_row = result.collect()[0]
        key_data = json.loads(first_row["key"])

        assert "id" in key_data
        assert key_data["id"] == 1

    def test_value_column_is_plain_json(self, sample_cdf_dataframe):
        """Test that value column contains plain JSON without wire format."""
        result = cdf_to_kafka_format_plain_json(
            sample_cdf_dataframe,
            key_columns=["id"],
            source_table="test_db.test_table",
            entity="test_entity",
        )

        first_row = result.collect()[0]
        value_bytes = bytes(first_row["value"])

        # Should NOT start with magic byte (no wire format)
        assert value_bytes[0] != 0x00

        # Should be valid JSON
        value_str = value_bytes.decode("utf-8")
        value_data = json.loads(value_str)

        # Should contain data columns
        assert "name" in value_data
        assert "email" in value_data
        assert "created_at" in value_data

        # Should NOT contain CDF metadata in value
        assert "_change_type" not in value_data
        assert "_commit_version" not in value_data
        assert "_commit_timestamp" not in value_data

    def test_multiple_key_columns(self, sample_cdf_dataframe):
        """Test with multiple key columns."""
        result = cdf_to_kafka_format_plain_json(
            sample_cdf_dataframe,
            key_columns=["id", "name"],
            source_table="test_db.test_table",
            entity="test_entity",
        )

        first_row = result.collect()[0]
        key_data = json.loads(first_row["key"])

        assert "id" in key_data
        assert "name" in key_data
        assert key_data["id"] == 1
        assert key_data["name"] == "Alice"

    def test_feature_set_name_extraction(self, sample_cdf_dataframe):
        """Test that feature_set_name is correctly extracted from source_table."""
        test_cases = [
            ("db.table", "table"),
            ("database.schema.table", "table"),
            ("db.table__latest", "table"),
            ("complex.db.schema.table__latest", "table"),
        ]

        for source_table, expected_feature_set in test_cases:
            result = cdf_to_kafka_format_plain_json(
                sample_cdf_dataframe,
                key_columns=["id"],
                source_table=source_table,
                entity="test_entity",
            )

            first_row = result.collect()[0]
            headers = first_row["headers"]
            header_dict = {h["key"]: h["value"] for h in headers}

            assert (
                header_dict["feature_set_name"].decode("utf-8") == expected_feature_set
            ), f"Failed for source_table: {source_table}"
