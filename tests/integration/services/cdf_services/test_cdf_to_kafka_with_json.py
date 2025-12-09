import json
import os
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


@pytest.mark.skip(reason="Skipping because testcontainers are not supported in Bietlejuice")
class TestDeltaCDFToKafkaServicePlainJSON:
    """Integration tests using Plain JSON format without Schema Registry."""

    @pytest.fixture(autouse=True)
    def setup_plain_json_mode(self):
        """Setup plain JSON mode by setting environment variable."""
        with patch.dict(os.environ, {"CDF_TO_KAFKA_USE_SCHEMA_REGISTRY": "false"}):
            import importlib

            import bietlejuice.services.cdf_services.cdf_to_kafka_config as config_module

            importlib.reload(config_module)
            yield
            importlib.reload(config_module)

    def test_cdf_to_kafka_complete_pipeline(
        self,
        spark_session,
        table,
        updated_table,
        kafka_options,
        temp_checkpoint_path,
    ):
        """Test the complete CDF to Kafka pipeline in plain JSON mode."""
        service = DeltaCDFToKafkaService(
            spark=spark_session,
            delta_table=table,
            key_columns=["id"],
            kafka_options=kafka_options,
            checkpoint_location=temp_checkpoint_path,
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

            assert len(headers) == 6

            headers_dict = dict(headers)
            assert headers_dict["_change_type"] in [b"insert", b"update_postimage"]
            assert headers_dict["_commit_version"] in [b"0", b"1"]
            assert isinstance(headers_dict["_commit_timestamp"], bytes)

            assert "schema_id" not in [
                key.decode() if isinstance(key, bytes) else key for key, _ in headers
            ]

            assert b"source_table" in [
                key.encode() if isinstance(key, str) else key for key, _ in headers
            ]
            assert b"feature_set_name" in [
                key.encode() if isinstance(key, str) else key for key, _ in headers
            ]
            assert b"entity" in [
                key.encode() if isinstance(key, str) else key for key, _ in headers
            ]

            key_data = json.loads(message.key)
            assert "id" in key_data

            value_data = json.loads(message.value.decode("utf-8"))
            assert "name" in value_data
            assert "email" in value_data
            assert "created_at" in value_data

            assert not message.value.startswith(b"\x00")

    def test_cdf_to_kafka_with_only_inserts(
        self,
        spark_session,
        table,
        kafka_options,
        temp_checkpoint_path,
    ):
        """Test that insert events are correctly sent to Kafka in plain JSON mode."""
        service = DeltaCDFToKafkaService(
            spark=spark_session,
            delta_table=table,
            key_columns=["id"],
            kafka_options=kafka_options,
            checkpoint_location=temp_checkpoint_path,
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

            assert "schema_id" not in [
                key.decode() if isinstance(key, bytes) else key
                for key, _ in message.headers
            ]

            value_data = json.loads(message.value.decode("utf-8"))
            assert "id" in value_data
            assert "name" in value_data
            assert "email" in value_data

            assert not message.value.startswith(b"\x00")

    def test_cdf_to_kafka_filters_only_insert_and_update_postimage(
        self,
        spark_session,
        table,
        deleted_table,
        kafka_options,
        temp_checkpoint_path,
    ):
        """Test that only insert and update_postimage events are sent in plain JSON mode."""
        service = DeltaCDFToKafkaService(
            spark=spark_session,
            delta_table=table,
            key_columns=["id"],
            kafka_options=kafka_options,
            checkpoint_location=temp_checkpoint_path,
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

        for message in messages:
            assert not message.value.startswith(b"\x00")
