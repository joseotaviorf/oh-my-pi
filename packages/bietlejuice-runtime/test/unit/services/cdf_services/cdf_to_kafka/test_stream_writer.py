"""Unit tests for KafkaStreamWriter."""

from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher import (
    CDFToKafkaMetricsPublisher,
)
from bietlejuice.services.cdf_services.cdf_to_kafka.stream_writer import (
    KafkaStreamWriter,
)


@pytest.fixture
def kafka_options():
    return {
        "kafka.bootstrap.servers": "localhost:9092",
        "topic": "test-topic",
    }


@pytest.fixture
def checkpoint_location():
    return "/tmp/checkpoint"


@pytest.fixture
def metrics_publisher():
    return MagicMock(spec=CDFToKafkaMetricsPublisher)


class TestKafkaStreamWriterInitialization:
    """Test that KafkaStreamWriter properly initializes its internal components."""

    def test_batch_processor_uses_same_metrics_collector(
        self,
        kafka_options,
        checkpoint_location,
        metrics_publisher,
    ):
        """
        Test that BatchProcessor uses the same MetricsCollector instance as the writer.

        This is critical for metrics correctness: the batch_processor collects metrics
        during foreachBatch execution, and the writer reads those metrics in the finally
        block to publish them. They MUST share the same instance.
        """
        writer = KafkaStreamWriter(
            checkpoint_location=checkpoint_location,
            kafka_options=kafka_options,
            metrics_publisher=metrics_publisher,
        )

        assert writer.batch_processor.metrics_collector is writer.metrics_collector


class TestKafkaStreamWriterWriteToKafka:
    """Tests for KafkaStreamWriter.write_to_kafka method."""

    def test_starts_streaming_query_with_correct_options(
        self,
        kafka_options,
        checkpoint_location,
        metrics_publisher,
    ):
        """Test that write_to_kafka starts streaming query with correct options."""
        writer = KafkaStreamWriter(
            checkpoint_location=checkpoint_location,
            kafka_options=kafka_options,
            metrics_publisher=metrics_publisher,
        )

        mock_df = MagicMock()
        mock_stream = MagicMock()
        mock_df.writeStream.foreachBatch.return_value = mock_stream
        mock_stream.option.return_value = mock_stream
        mock_stream.trigger.return_value = mock_stream
        mock_query = MagicMock()
        mock_query.exception.return_value = None
        mock_query.isActive = True
        mock_stream.start.return_value = mock_query

        writer.write_to_kafka(mock_df)

        mock_df.writeStream.foreachBatch.assert_called_once_with(
            writer.batch_processor.process_batch
        )
        mock_stream.option.assert_called_once_with(
            "checkpointLocation", checkpoint_location
        )
        mock_stream.trigger.assert_called_once_with(availableNow=True)
        mock_query.awaitTermination.assert_called_once()
        mock_query.stop.assert_called_once()

    def test_raises_exception_from_query(
        self,
        kafka_options,
        checkpoint_location,
        metrics_publisher,
    ):
        """Test that exceptions from query are re-raised."""
        writer = KafkaStreamWriter(
            checkpoint_location=checkpoint_location,
            kafka_options=kafka_options,
            metrics_publisher=metrics_publisher,
        )

        mock_df = MagicMock()
        mock_stream = MagicMock()
        mock_df.writeStream.foreachBatch.return_value = mock_stream
        mock_stream.option.return_value = mock_stream
        mock_stream.trigger.return_value = mock_stream
        mock_query = MagicMock()
        mock_query.exception.return_value = RuntimeError("Query failed")
        mock_stream.start.return_value = mock_query

        with pytest.raises(RuntimeError, match="Query failed"):
            writer.write_to_kafka(mock_df)

    @patch.dict("os.environ", {"ENVIRONMENT": "prod"})
    def test_publishes_metrics_in_production(
        self,
        kafka_options,
        checkpoint_location,
        metrics_publisher,
    ):
        """Test that metrics are published in production environment."""
        writer = KafkaStreamWriter(
            checkpoint_location=checkpoint_location,
            kafka_options=kafka_options,
            metrics_publisher=metrics_publisher,
        )

        mock_df = MagicMock()
        mock_stream = MagicMock()
        mock_df.writeStream.foreachBatch.return_value = mock_stream
        mock_stream.option.return_value = mock_stream
        mock_stream.trigger.return_value = mock_stream
        mock_query = MagicMock()
        mock_query.exception.return_value = None
        mock_stream.start.return_value = mock_query

        writer.write_to_kafka(mock_df)

        metrics_publisher.record_write.assert_called_once()
        metrics_publisher.flush.assert_called_once()

    @patch.dict("os.environ", {"ENVIRONMENT": "dev"})
    def test_skips_metrics_in_non_production(
        self,
        kafka_options,
        checkpoint_location,
        metrics_publisher,
    ):
        """Test that metrics are skipped in non-production environments."""
        writer = KafkaStreamWriter(
            checkpoint_location=checkpoint_location,
            kafka_options=kafka_options,
            metrics_publisher=metrics_publisher,
        )

        mock_df = MagicMock()
        mock_stream = MagicMock()
        mock_df.writeStream.foreachBatch.return_value = mock_stream
        mock_stream.option.return_value = mock_stream
        mock_stream.trigger.return_value = mock_stream
        mock_query = MagicMock()
        mock_query.exception.return_value = None
        mock_stream.start.return_value = mock_query

        writer.write_to_kafka(mock_df)

        metrics_publisher.record_write.assert_not_called()
