import json
import struct
from datetime import datetime

import pytest

from bietlejuice.services.cdf_services.cdf_to_kafka.transformations.wire_format import (
    _create_confluent_encoder_udf,
    cdf_to_kafka_format_with_schema_registry,
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


class TestCreateConfluentEncoderUdf:
    """Unit tests for create_confluent_encoder_udf function."""

    def test_wire_format_structure(self, spark_session):
        """Test that the UDF produces correct wire format structure."""
        json_string = '{"name": "Alice", "id": 1}'
        schema_id = 12345

        encoder_udf = _create_confluent_encoder_udf(schema_id)
        df = spark_session.createDataFrame([(json_string,)], ["json"])
        result = df.select(encoder_udf(df["json"]).alias("encoded")).collect()[0][
            "encoded"
        ]

        assert isinstance(result, (bytes, bytearray))
        encoded = bytes(result)
        assert encoded[0] == 0x00
        assert struct.unpack(">I", encoded[1:5])[0] == schema_id
        assert encoded[5:] == json_string.encode("utf-8")

    def test_different_schema_ids(self, spark_session):
        """Test encoding with different schema IDs."""
        json_string = '{"test": "data"}'

        for schema_id in [1, 100, 65535, 2147483647]:
            encoder_udf = _create_confluent_encoder_udf(schema_id)
            df = spark_session.createDataFrame([(json_string,)], ["json"])
            result = df.select(encoder_udf(df["json"]).alias("encoded")).collect()[0][
                "encoded"
            ]

            encoded = bytes(result)
            decoded_schema_id = struct.unpack(">I", encoded[1:5])[0]
            assert decoded_schema_id == schema_id

    def test_json_payload_integrity(self, spark_session):
        """Test that JSON payload is preserved correctly."""
        test_data = {"user": "test", "value": 42, "nested": {"key": "value"}}
        json_string = json.dumps(test_data)
        schema_id = 999

        encoder_udf = _create_confluent_encoder_udf(schema_id)
        df = spark_session.createDataFrame([(json_string,)], ["json"])
        result = df.select(encoder_udf(df["json"]).alias("encoded")).collect()[0][
            "encoded"
        ]

        encoded = bytes(result)
        json_payload = encoded[5:].decode("utf-8")
        decoded_data = json.loads(json_payload)

        assert decoded_data == test_data

    def test_batch_encoding(self, spark_session):
        """Test that UDF correctly encodes multiple rows in a batch."""
        schema_id = 12345
        test_data = [
            ('{"id":1,"name":"Alice"}',),
            ('{"id":2,"name":"Bob"}',),
            ('{"id":3,"name":"Charlie"}',),
        ]

        encoder_udf = _create_confluent_encoder_udf(schema_id)
        df = spark_session.createDataFrame(test_data, ["json"])
        result = df.select(encoder_udf(df["json"]).alias("encoded")).collect()

        # Verify all rows have the same schema_id prefix
        for row in result:
            encoded = bytes(row["encoded"])
            assert encoded[0] == 0x00
            assert struct.unpack(">I", encoded[1:5])[0] == schema_id


class TestCdfToKafkaFormatWithSchemaRegistry:
    """Unit tests for cdf_to_kafka_format_with_schema_registry function."""

    def test_headers_include_schema_id(self, sample_cdf_dataframe):
        """Test that headers include schema_id in wire format mode."""
        schema_id = 12345
        result = cdf_to_kafka_format_with_schema_registry(
            sample_cdf_dataframe,
            key_columns=["id"],
            source_table="test_db.test_table",
            schema_id=schema_id,
            entity="test_entity",
        )

        first_row = result.collect()[0]
        headers = first_row["headers"]

        header_dict = {h["key"]: h["value"] for h in headers}

        # Should include schema_id header
        assert "schema_id" in header_dict
        assert header_dict["schema_id"].decode("utf-8") == str(schema_id)

        # Should include all standard headers
        assert "source_table" in header_dict
        assert "_change_type" in header_dict
        assert "feature_set_name" in header_dict
        assert "entity" in header_dict

    def test_value_column_wire_format(self, sample_cdf_dataframe):
        """Test that value column is encoded with Confluent wire format."""
        schema_id = 12345
        result = cdf_to_kafka_format_with_schema_registry(
            sample_cdf_dataframe,
            key_columns=["id"],
            source_table="test_db.test_table",
            schema_id=schema_id,
            entity="test_entity",
        )

        first_row = result.collect()[0]
        encoded_value = bytes(first_row["value"])

        # Should start with magic byte
        assert encoded_value[0] == 0x00

        # Should have correct schema_id
        decoded_schema_id = struct.unpack(">I", encoded_value[1:5])[0]
        assert decoded_schema_id == schema_id

        # JSON payload should be valid
        json_payload = encoded_value[5:].decode("utf-8")
        value_data = json.loads(json_payload)

        assert "name" in value_data
        assert "email" in value_data
        assert "created_at" in value_data

        # Should not contain CDF metadata in value
        assert "_change_type" not in value_data
        assert "_commit_version" not in value_data
        assert "_commit_timestamp" not in value_data

    def test_key_column_content(self, sample_cdf_dataframe):
        """Test that key column contains the specified key columns as JSON."""
        result = cdf_to_kafka_format_with_schema_registry(
            sample_cdf_dataframe,
            key_columns=["id"],
            source_table="test_db.test_table",
            schema_id=12345,
            entity="test_entity",
        )

        first_row = result.collect()[0]
        key_data = json.loads(first_row["key"])

        assert "id" in key_data
        assert key_data["id"] == 1

    def test_multiple_key_columns(self, sample_cdf_dataframe):
        """Test with multiple key columns."""
        result = cdf_to_kafka_format_with_schema_registry(
            sample_cdf_dataframe,
            key_columns=["id", "name"],
            source_table="test_db.test_table",
            schema_id=12345,
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
            result = cdf_to_kafka_format_with_schema_registry(
                sample_cdf_dataframe,
                key_columns=["id"],
                source_table=source_table,
                schema_id=12345,
                entity="test_entity",
            )

            first_row = result.collect()[0]
            headers = first_row["headers"]
            header_dict = {h["key"]: h["value"] for h in headers}

            assert (
                header_dict["feature_set_name"].decode("utf-8") == expected_feature_set
            ), f"Failed for source_table: {source_table}"
