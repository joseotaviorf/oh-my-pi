"""Unit tests for cdf_to_kafka_format wrapper function.

This test module focuses on testing the wrapper function that delegates to
specific implementations. Detailed tests for each implementation are in:
- test_wire_format.py
- test_plain_json.py
"""

import json
import struct
from datetime import datetime

import pytest

from bietlejuice.services.cdf_services.cdf_to_kafka.transformations.common import (
    cdf_to_kafka_format,
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


class TestCdfToKafkaFormatWrapper:
    """Unit tests for cdf_to_kafka_format wrapper function."""

    def test_raises_error_when_schema_id_missing_with_registry(
        self, sample_cdf_dataframe
    ):
        """Test that wrapper raises ValueError when schema_id is None but use_schema_registry=True."""
        with pytest.raises(
            ValueError, match="schema_id is required when use_schema_registry=True"
        ):
            cdf_to_kafka_format(
                sample_cdf_dataframe,
                key_columns=["id"],
                source_table="test_db.test_table",
                schema_id=None,
                entity="test_entity",
                use_schema_registry=True,
            )

    def test_delegates_to_wire_format_when_registry_enabled(self, sample_cdf_dataframe):
        """Test that wrapper correctly delegates to wire format implementation."""
        schema_id = 12345
        result = cdf_to_kafka_format(
            sample_cdf_dataframe,
            key_columns=["id"],
            source_table="test_db.test_table",
            schema_id=schema_id,
            entity="test_entity",
            use_schema_registry=True,
        )

        first_row = result.collect()[0]
        encoded_value = bytes(first_row["value"])

        # Verify wire format: magic byte + schema_id
        assert encoded_value[0] == 0x00
        decoded_schema_id = struct.unpack(">I", encoded_value[1:5])[0]
        assert decoded_schema_id == schema_id

        # Verify schema_id in headers
        headers = first_row["headers"]
        header_dict = {h["key"]: h["value"] for h in headers}
        assert "schema_id" in header_dict

    def test_delegates_to_plain_json_when_registry_disabled(self, sample_cdf_dataframe):
        """Test that wrapper correctly delegates to plain JSON implementation."""
        result = cdf_to_kafka_format(
            sample_cdf_dataframe,
            key_columns=["id"],
            source_table="test_db.test_table",
            schema_id=None,
            entity="test_entity",
            use_schema_registry=False,
        )

        first_row = result.collect()[0]
        value_bytes = bytes(first_row["value"])

        # Should NOT start with magic byte (plain JSON)
        assert value_bytes[0] != 0x00

        # Should be valid JSON
        value_str = value_bytes.decode("utf-8")
        value_data = json.loads(value_str)
        assert "name" in value_data

        # Verify no schema_id in headers
        headers = first_row["headers"]
        header_dict = {h["key"]: h["value"] for h in headers}
        assert "schema_id" not in header_dict

    def test_key_columns_passed_to_implementation(self, sample_cdf_dataframe):
        """Test that multiple key_columns are correctly handled."""
        result = cdf_to_kafka_format(
            sample_cdf_dataframe,
            key_columns=["id", "name"],
            source_table="test_db.test_table",
            schema_id=12345,
            entity="test_entity",
            use_schema_registry=True,
        )

        first_row = result.collect()[0]
        key_data = json.loads(first_row["key"])
        assert "id" in key_data
        assert "name" in key_data
