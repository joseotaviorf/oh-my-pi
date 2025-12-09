import json
import os
import struct
from unittest.mock import patch

import pytest

from bietlejuice.services.cdf_services.cdf_to_kafka_service import DeltaCDFToKafkaService


def _read_kafka_messages(topic: str, bootstrap_servers: str, auto_offset_reset: str):
    """Read messages from Kafka topic."""
    import itertools

    from kafka import KafkaConsumer

    consumer = KafkaConsumer(
        topic,
        bootstrap_servers=bootstrap_servers,
        auto_offset_reset=auto_offset_reset,
        enable_auto_commit=False,
    )

    messages = consumer.poll(timeout_ms=1000)

    if messages:
        messages = list(itertools.chain.from_iterable(messages.values()))

    return messages


def _decode_confluent_wire_format(encoded_bytes: bytes) -> tuple[int, dict]:
    """Decode Confluent wire format to extract schema_id and JSON payload.

    Args:
        encoded_bytes: Bytes in Confluent wire format

    Returns:
        Tuple of (schema_id, json_data)
    """
    magic_byte = encoded_bytes[0]
    assert magic_byte == 0x00, f"Expected magic byte 0x00, got {hex(magic_byte)}"

    schema_id = struct.unpack(">I", encoded_bytes[1:5])[0]

    json_bytes = encoded_bytes[5:]
    json_data = json.loads(json_bytes.decode("utf-8"))

    return schema_id, json_data


@pytest.mark.skip(reason="Skipping wire format tests because, in Bietlejuice, we can't find pyspark.sql.streaming modules")
class TestDeltaCDFToKafkaServiceWireFormat:
    """Integration tests using Confluent Wire Format with Schema Registry."""

    @pytest.fixture(autouse=True)
    def setup_wire_format_mode(self):
        """Setup wire format mode by setting environment variable."""
        with patch.dict(os.environ, {"CDF_TO_KAFKA_USE_SCHEMA_REGISTRY": "true"}):
            import importlib

            import bietlejuice.services.cdf_services.cdf_to_kafka_config as config_module

            importlib.reload(config_module)
            yield
            importlib.reload(config_module)

    def test_cdf_to_kafka_complete_pipeline(
        self,
        mock_schema_registry,
        spark_session,
        table,
        updated_table,
        kafka_options,
        temp_checkpoint_path,
        schema_registry_config,
    ):
        """Test the complete CDF to Kafka pipeline with wire format."""
        service = DeltaCDFToKafkaService(
            spark=spark_session,
            delta_table=table,
            key_columns=["id"],
            kafka_options=kafka_options,
            checkpoint_location=temp_checkpoint_path,
            schema_registry_url=schema_registry_config["url"],
            schema_registry_api_key=schema_registry_config["api_key"],
            schema_registry_api_secret=schema_registry_config["api_secret"],
            entity="test_entity",
        )
        service.run()

        messages = _read_kafka_messages(
            kafka_options["topic"], kafka_options["kafka.bootstrap.servers"], "earliest"
        )

        assert len(messages) > 1

        for message in messages:
            headers = message.headers
            assert isinstance(headers, list)
            assert len(headers) == 7

            headers_dict = dict(headers)
            assert headers_dict["_change_type"] in [b"insert", b"update_postimage"]
            assert headers_dict["_commit_version"] in [b"0", b"1"]
            assert isinstance(headers_dict["_commit_timestamp"], bytes)
            assert headers_dict["schema_id"] == b"1"
            assert b"source_table" in [
                key.encode() if isinstance(key, str) else key for key, _ in headers
            ]
            assert b"feature_set_name" in [
                key.encode() if isinstance(key, str) else key for key, _ in headers
            ]

            key_data = json.loads(message.key)
            assert "id" in key_data

            decoded_schema_id, value_data = _decode_confluent_wire_format(message.value)
            assert decoded_schema_id == 1
            assert "name" in value_data
            assert "email" in value_data
            assert "created_at" in value_data

    def test_cdf_to_kafka_filters_only_insert_and_update_postimage(
        self,
        mock_schema_registry,
        spark_session,
        table,
        deleted_table,
        kafka_options,
        temp_checkpoint_path,
        schema_registry_config,
    ):
        """Test that only insert and update_postimage events are sent to Kafka."""
        service = DeltaCDFToKafkaService(
            spark=spark_session,
            delta_table=table,
            key_columns=["id"],
            kafka_options=kafka_options,
            checkpoint_location=temp_checkpoint_path,
            schema_registry_url=schema_registry_config["url"],
            schema_registry_api_key=schema_registry_config["api_key"],
            schema_registry_api_secret=schema_registry_config["api_secret"],
            entity="test_entity",
        )
        service.run()

        messages = _read_kafka_messages(
            kafka_options["topic"], kafka_options["kafka.bootstrap.servers"], "earliest"
        )

        assert len(messages) > 0

        change_types = [
            dict(message.headers)["_change_type"].decode() for message in messages
        ]
        assert all(ct in ["insert", "update_postimage"] for ct in change_types), (
            f"Found unexpected change types: {set(change_types)}"
        )

        assert "delete" not in change_types
        assert "update_preimage" not in change_types

    def test_cdf_to_kafka_with_only_inserts(
        self,
        mock_schema_registry,
        spark_session,
        table,
        kafka_options,
        temp_checkpoint_path,
        schema_registry_config,
    ):
        """Test that insert events are correctly sent to Kafka with wire format."""
        service = DeltaCDFToKafkaService(
            spark=spark_session,
            delta_table=table,
            key_columns=["id"],
            kafka_options=kafka_options,
            checkpoint_location=temp_checkpoint_path,
            schema_registry_url=schema_registry_config["url"],
            schema_registry_api_key=schema_registry_config["api_key"],
            schema_registry_api_secret=schema_registry_config["api_secret"],
            entity="test_entity",
        )
        service.run()

        messages = _read_kafka_messages(
            kafka_options["topic"], kafka_options["kafka.bootstrap.servers"], "earliest"
        )

        assert len(messages) == 3

        for message in messages:
            headers_dict = dict(message.headers)
            assert headers_dict["_change_type"] == b"insert"
            assert headers_dict["schema_id"] == b"1"

            _, value_data = _decode_confluent_wire_format(message.value)
            assert "id" in value_data
            assert "name" in value_data
            assert "email" in value_data

    def test_cdf_to_kafka_includes_update_postimage(
        self,
        mock_schema_registry,
        spark_session,
        table,
        updated_table,
        kafka_options,
        temp_checkpoint_path,
        schema_registry_config,
    ):
        """Test that update_postimage events are included with wire format."""
        service = DeltaCDFToKafkaService(
            spark=spark_session,
            delta_table=table,
            key_columns=["id"],
            kafka_options=kafka_options,
            checkpoint_location=temp_checkpoint_path,
            schema_registry_url=schema_registry_config["url"],
            schema_registry_api_key=schema_registry_config["api_key"],
            schema_registry_api_secret=schema_registry_config["api_secret"],
            entity="test_entity",
        )
        service.run()

        messages = _read_kafka_messages(
            kafka_options["topic"], kafka_options["kafka.bootstrap.servers"], "earliest"
        )

        assert len(messages) > 0

        change_types = [
            dict(message.headers)["_change_type"].decode() for message in messages
        ]

        assert "insert" in change_types
        assert all(ct in ["insert", "update_postimage"] for ct in change_types)

        for message in messages:
            _, value_data = _decode_confluent_wire_format(message.value)
            assert message.value.startswith(b"\x00")
