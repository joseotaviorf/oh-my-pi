"""Unit tests for BatchProcessor."""

from unittest.mock import MagicMock

import pytest

from bietlejuice.services.cdf_services.cdf_to_kafka.batch_processor import (
    BatchProcessor,
)
from bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_collector import (
    MetricsCollector,
)


@pytest.fixture
def kafka_options():
    return {
        "kafka.bootstrap.servers": "localhost:9092",
        "topic": "test-topic",
    }


@pytest.fixture
def metrics_collector():
    return MagicMock(spec=MetricsCollector)


class TestBatchProcessorProcessBatch:
    """Tests for BatchProcessor.process_batch method."""

    def test_skips_empty_batch(self, kafka_options, metrics_collector):
        """Test that empty batches are skipped."""
        processor = BatchProcessor(
            kafka_options=kafka_options,
            metrics_collector=metrics_collector,
        )

        mock_batch_df = MagicMock()
        mock_batch_df.isEmpty.return_value = True

        processor.process_batch(mock_batch_df, batch_id=0)

        mock_batch_df.persist.assert_not_called()
        metrics_collector.collect_batch_metrics.assert_not_called()

    def test_unpersists_batch_even_on_error(self, kafka_options, metrics_collector):
        """Test that batch is unpersisted even when an error occurs."""
        processor = BatchProcessor(
            kafka_options=kafka_options,
            metrics_collector=metrics_collector,
        )

        mock_batch_df = MagicMock()
        mock_batch_df.isEmpty.return_value = False
        mock_kafka_df = MagicMock()
        mock_batch_df.drop.return_value = mock_kafka_df
        mock_kafka_df.write.format.return_value.options.return_value.save.side_effect = Exception(
            "Kafka error"
        )

        with pytest.raises(Exception, match="Kafka error"):
            processor.process_batch(mock_batch_df, batch_id=1)

        mock_batch_df.persist.assert_called_once()
        mock_batch_df.unpersist.assert_called_once()

    def test_writes_to_kafka_and_collects_metrics(
        self, kafka_options, metrics_collector
    ):
        """Test that data is written to Kafka and metrics are collected."""
        processor = BatchProcessor(
            kafka_options=kafka_options,
            metrics_collector=metrics_collector,
        )

        mock_batch_df = MagicMock()
        mock_batch_df.isEmpty.return_value = False
        mock_kafka_df = MagicMock()
        mock_batch_df.drop.return_value = mock_kafka_df

        mock_writer = MagicMock()
        mock_kafka_df.write.format.return_value = mock_writer
        mock_writer.options.return_value = mock_writer

        processor.process_batch(mock_batch_df, batch_id=42)

        mock_batch_df.drop.assert_called_once_with("_change_type")
        mock_kafka_df.write.format.assert_called_once_with("kafka")
        mock_writer.options.assert_called_once_with(**kafka_options)
        mock_writer.save.assert_called_once()
        metrics_collector.collect_batch_metrics.assert_called_once_with(
            mock_batch_df, 42
        )
        mock_batch_df.unpersist.assert_called_once()

    def test_does_not_collect_metrics_on_write_failure(
        self, kafka_options, metrics_collector
    ):
        """Test that metrics are not collected when Kafka write fails."""
        processor = BatchProcessor(
            kafka_options=kafka_options,
            metrics_collector=metrics_collector,
        )

        mock_batch_df = MagicMock()
        mock_batch_df.isEmpty.return_value = False
        mock_kafka_df = MagicMock()
        mock_batch_df.drop.return_value = mock_kafka_df
        mock_kafka_df.write.format.return_value.options.return_value.save.side_effect = Exception(
            "Kafka error"
        )

        with pytest.raises(Exception):
            processor.process_batch(mock_batch_df, batch_id=1)

        metrics_collector.collect_batch_metrics.assert_not_called()
