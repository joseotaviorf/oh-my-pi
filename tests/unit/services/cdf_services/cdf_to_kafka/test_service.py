"""Unit tests for DeltaCDFToKafkaService."""

from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.services.cdf_services.cdf_to_kafka.service import (
    DeltaCDFToKafkaService,
)


@pytest.fixture
def spark_session_mock():
    return MagicMock()


@pytest.fixture
def kafka_options():
    return {
        "kafka.bootstrap.servers": "localhost:9092",
        "topic": "test-topic",
    }


@pytest.fixture
def checkpoint_location():
    return "/tmp/checkpoint"


class TestDeltaCDFToKafkaServiceInitialization:
    """Tests for DeltaCDFToKafkaService initialization."""

    @pytest.mark.parametrize(
        "delta_table,expected_feature_set",
        [
            ("db.feature_set__latest", "feature_set"),
            ("db.my_table__latest", "my_table"),
            ("database.schema.table__latest", "table"),
            ("db.simple_table", "simple_table"),
        ],
    )
    @patch("bietlejuice.services.cdf_services.cdf_to_kafka.service.DeltaCDFReader")
    @patch("bietlejuice.services.cdf_services.cdf_to_kafka.service.KafkaStreamWriter")
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.service.CDFToKafkaMetricsPublisher"
    )
    def test_extracts_feature_set_name_correctly(
        self,
        mock_metrics_publisher,
        mock_writer,
        mock_reader,
        delta_table,
        expected_feature_set,
        spark_session_mock,
        kafka_options,
        checkpoint_location,
    ):
        """Test that feature_set_name is correctly extracted from delta_table."""
        service = DeltaCDFToKafkaService(
            spark=spark_session_mock,
            delta_table=delta_table,
            key_columns=["id"],
            kafka_options=kafka_options,
            checkpoint_location=checkpoint_location,
            entity="test_entity",
        )

        assert service.feature_set_name == expected_feature_set
        mock_metrics_publisher.assert_called_once_with(
            entity="test_entity",
            feature_set_name=expected_feature_set,
        )


class TestDeltaCDFToKafkaServiceRun:
    """Tests for DeltaCDFToKafkaService.run method."""

    @patch("bietlejuice.services.cdf_services.cdf_to_kafka.service.config")
    @patch("bietlejuice.services.cdf_services.cdf_to_kafka.service.cdf_to_kafka_format")
    @patch("bietlejuice.services.cdf_services.cdf_to_kafka.service.DeltaCDFReader")
    @patch("bietlejuice.services.cdf_services.cdf_to_kafka.service.KafkaStreamWriter")
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.service.CDFToKafkaMetricsPublisher"
    )
    def test_run_executes_full_pipeline(
        self,
        mock_metrics_publisher,
        mock_writer,
        mock_reader,
        mock_cdf_to_kafka_format,
        mock_config,
        spark_session_mock,
        kafka_options,
        checkpoint_location,
    ):
        """Test that run() executes the full pipeline correctly."""
        mock_cleaned_cdf = MagicMock()
        schema_id = 456
        mock_reader_instance = MagicMock()
        mock_reader_instance.prepare_cdf_stream.return_value = (
            mock_cleaned_cdf,
            schema_id,
        )
        mock_reader.return_value = mock_reader_instance
        mock_config.use_schema_registry = True

        mock_transformed_df = MagicMock()
        mock_cdf_to_kafka_format.return_value = mock_transformed_df

        mock_writer_instance = MagicMock()
        mock_writer.return_value = mock_writer_instance

        service = DeltaCDFToKafkaService(
            spark=spark_session_mock,
            delta_table="db.table__latest",
            key_columns=["id", "tenant"],
            kafka_options=kafka_options,
            checkpoint_location=checkpoint_location,
            entity="test_entity",
        )
        service.run()

        mock_reader_instance.validate_table.assert_called_once()
        mock_reader_instance.prepare_cdf_stream.assert_called_once_with(
            kafka_topic="test-topic"
        )
        mock_cdf_to_kafka_format.assert_called_once_with(
            cdf_dataframe=mock_cleaned_cdf,
            key_columns=["id", "tenant"],
            source_table="db.table__latest",
            schema_id=schema_id,
            entity="test_entity",
            use_schema_registry=True,
        )
        mock_writer_instance.write_to_kafka.assert_called_once_with(
            df=mock_transformed_df
        )
