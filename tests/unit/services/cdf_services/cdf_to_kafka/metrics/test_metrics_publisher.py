"""Unit tests for CDFToKafkaMetricsPublisher."""

from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher import (
    CDFToKafkaMetricsPublisher,
)
from bietlejuice.services.cdf_services.cdf_to_kafka.models.pipeline_metrics import (
    PipelineMetrics,
)


class TestCDFToKafkaMetricsPublisherInitialization:
    """Tests for CDFToKafkaMetricsPublisher initialization."""

    @patch.dict(
        "os.environ",
        {
            "PUSH_GATEWAY_OTLP_ENDPOINT": "http://custom-endpoint/v1/metrics",
            "PUSH_GATEWAY_EXPORT_TIMEOUT_MS": "60000",
        },
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.metrics"
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.MeterProvider"
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.PeriodicExportingMetricReader"
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.OTLPMetricExporter"
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.Resource"
    )
    def test_configures_otel_with_environment_variables(
        self, mock_resource, mock_exporter, mock_reader, mock_provider, mock_metrics
    ):
        """Test that OpenTelemetry is configured with environment variables."""
        CDFToKafkaMetricsPublisher(
            entity="test_entity",
            feature_set_name="test_feature_set",
            job_name="test-job",
        )

        mock_exporter.assert_called_once()
        call_kwargs = mock_exporter.call_args.kwargs
        assert call_kwargs["endpoint"] == "http://custom-endpoint/v1/metrics"
        assert call_kwargs["timeout"] == 60

        mock_resource.create.assert_called_once()
        resource_attrs = mock_resource.create.call_args[0][0]
        assert resource_attrs["job"] == "test-job"


class TestCDFToKafkaMetricsPublisherRecordWrite:
    """Tests for CDFToKafkaMetricsPublisher.record_write method."""

    @pytest.fixture
    def mock_publisher(self):
        """Create a publisher with mocked counters and gauges."""
        with (
            patch(
                "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.metrics"
            ),
            patch(
                "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.MeterProvider"
            ),
            patch(
                "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.PeriodicExportingMetricReader"
            ),
            patch(
                "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.OTLPMetricExporter"
            ),
            patch(
                "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.Resource"
            ),
        ):
            publisher = CDFToKafkaMetricsPublisher(
                entity="test_entity",
                feature_set_name="test_feature_set",
            )

            publisher.job_runs_counter = MagicMock()
            publisher.messages_written_counter = MagicMock()
            publisher.message_bytes_written_counter = MagicMock()
            publisher.messages_by_change_type_counter = MagicMock()
            publisher.job_duration_gauge = MagicMock()

            return publisher

    def test_records_all_metrics(self, mock_publisher):
        """Test that all metrics are recorded correctly."""
        pipeline_metrics = PipelineMetrics(
            change_type_counts={"insert": 10, "update_postimage": 5},
            change_type_bytes={"insert": 1000, "update_postimage": 500},
            total_messages=15,
            total_bytes=1500,
        )

        mock_publisher.record_write(
            status="success",
            duration_seconds=15.75,
            pipeline_metrics=pipeline_metrics,
        )

        expected_attrs = {
            "status": "success",
            "feature_set": "test_feature_set",
            "entity": "test_entity",
        }

        mock_publisher.job_runs_counter.add.assert_called_once_with(
            1, attributes=expected_attrs
        )
        mock_publisher.messages_written_counter.add.assert_called_once_with(
            15, attributes=expected_attrs
        )
        mock_publisher.message_bytes_written_counter.add.assert_called_once_with(
            1500, attributes=expected_attrs
        )
        mock_publisher.job_duration_gauge.set.assert_called_once_with(
            15.75, attributes=expected_attrs
        )
        assert mock_publisher.messages_by_change_type_counter.add.call_count == 2


class TestCDFToKafkaMetricsPublisherFlush:
    """Tests for CDFToKafkaMetricsPublisher.flush method."""

    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.metrics"
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.MeterProvider"
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.PeriodicExportingMetricReader"
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.OTLPMetricExporter"
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.Resource"
    )
    def test_calls_shutdown_only(
        self, mock_resource, mock_exporter, mock_reader, mock_provider, mock_metrics
    ):
        """Test that flush calls only shutdown (which includes internal flush)."""
        publisher = CDFToKafkaMetricsPublisher(
            entity="test_entity",
            feature_set_name="test_feature_set",
        )

        publisher.flush(timeout_seconds=45)

        publisher.meter_provider.shutdown.assert_called_once_with(timeout_millis=45000)

    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.metrics"
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.MeterProvider"
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.PeriodicExportingMetricReader"
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.OTLPMetricExporter"
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher.Resource"
    )
    def test_does_not_raise_on_exception(
        self, mock_resource, mock_exporter, mock_reader, mock_provider, mock_metrics
    ):
        """Test that flush does not raise on exception."""
        mock_provider_instance = MagicMock()
        mock_provider_instance.shutdown.side_effect = Exception("Error")
        mock_provider.return_value = mock_provider_instance

        publisher = CDFToKafkaMetricsPublisher(
            entity="test_entity",
            feature_set_name="test_feature_set",
        )

        publisher.flush()
