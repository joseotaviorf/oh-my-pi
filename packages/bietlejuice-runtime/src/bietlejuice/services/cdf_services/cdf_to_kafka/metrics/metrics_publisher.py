import logging
import os
from typing import Any

from opentelemetry import metrics
from opentelemetry.exporter.otlp.proto.http.metric_exporter import (
    OTLPMetricExporter,
)
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource

from bietlejuice.services.cdf_services.cdf_to_kafka.models.pipeline_metrics import (
    PipelineMetrics,
)

logger = logging.getLogger(__name__)


class CDFToKafkaMetricsPublisher:
    """
    Publisher for CDF to Kafka pipeline metrics using OpenTelemetry.
    Designed for short-lived batch jobs.

    ## Design Decisions & History

    ### Temporality: CUMULATIVE (not DELTA)
    - **Reason**: Prometheus Remote Write Exporter doesn't support DELTA counters
    - **Impact**: Counters accumulate values, use `increase()` in PromQL for per-execution deltas
    - **Alternative Considered**: DELTA temporality (semantically better for batch jobs)
    - **When it failed**: "invalid temporality and type combination" errors in collector logs

    ### Flush Strategy: Only shutdown() (not force_flush() + shutdown())
    - **Reason**: MeterProvider.shutdown() performs internal flush, calling force_flush() first causes duplicates
    - **Impact**: Eliminates double metric exports per job execution
    - **When it failed**: `count_over_time()` returned 2 instead of 1 per execution

    Metric attributes (feature_set, entity, status, change_type) are used as labels.
    """

    def __init__(
        self,
        entity: str,
        feature_set_name: str,
        job_name: str = "cdf-to-kafka",
    ):
        self.entity = entity
        self.feature_set_name = feature_set_name
        self.job_name = job_name

        self._setup_metrics()

    def _setup_metrics(self) -> None:
        """Configure OpenTelemetry metrics provider for short-lived jobs."""

        endpoint = os.environ.get(
            "PUSH_GATEWAY_OTLP_ENDPOINT",
            "https://pushgateway-collector.apps.data-prd.habitat.zone/v1/metrics",
        )

        export_interval = int(os.environ.get("PUSH_GATEWAY_EXPORT_INTERVAL_MS", "5000"))
        export_timeout = int(os.environ.get("PUSH_GATEWAY_EXPORT_TIMEOUT_MS", "30000"))

        resource = Resource.create(
            {
                "job": self.job_name,
                "app": os.environ.get("DATABRICKS_APP_NAME", "unknown"),
                "hostname": os.environ.get("DATABRICKS_HOST", ""),
            }
        )

        otlp_exporter = OTLPMetricExporter(
            endpoint=endpoint,
            headers={"Content-Type": "application/x-protobuf"},
            timeout=export_timeout // 1000,
        )

        metric_reader = PeriodicExportingMetricReader(
            exporter=otlp_exporter,
            export_interval_millis=export_interval,
            export_timeout_millis=export_timeout,
        )

        self.meter_provider = MeterProvider(
            resource=resource,
            metric_readers=[metric_reader],
        )

        metrics.set_meter_provider(self.meter_provider)

        meter = metrics.get_meter(self.job_name)

        self._create_counters(meter)
        self._create_gauges(meter)

    def _create_counters(self, meter: Any) -> None:
        """
        Create counter metrics for tracking work done.

        ## Design Notes

        ### CUMULATIVE Temporality Choice
        - **What it means**: Each export contains the total accumulated value since process start
        - **Why chosen**: Prometheus ecosystem requires CUMULATIVE for counters
        - **PromQL workaround**: Use `increase()` to get per-execution deltas:
          ```
          increase(cdf_to_kafka_messages_written[5m])  # messages in last 5 minutes
          ```
        """
        self.job_runs_counter = meter.create_counter(
            name="cdf_to_kafka_job_runs",
            description="Number of job executions",
            unit="1",
        )

        self.messages_written_counter = meter.create_counter(
            name="cdf_to_kafka_messages_written",
            description="Messages written to Kafka",
            unit="1",
        )

        self.message_bytes_written_counter = meter.create_counter(
            name="cdf_to_kafka_message_bytes_written",
            description="Bytes written to Kafka",
            unit="By",
        )

        self.messages_by_change_type_counter = meter.create_counter(
            name="cdf_to_kafka_messages_by_change_type",
            description="Messages per change type",
            unit="1",
        )

    def _create_gauges(self, meter: Any) -> None:
        """
        Create gauge metrics for point-in-time measurements.

        Only duration is a gauge - it's a measurement of the last execution,
        not something to be summed over time.
        """
        self.job_duration_gauge = meter.create_gauge(
            name="cdf_to_kafka_job_duration_seconds",
            description="Duration of the job execution in seconds",
            unit="s",
        )

    def record_write(
        self,
        status: str,
        duration_seconds: float,
        pipeline_metrics: PipelineMetrics,
    ) -> None:
        """
        Record metrics for a single job execution.

        Args:
            status: Job status ('success' | 'error')
            duration_seconds: Job duration in seconds
            pipeline_metrics: Aggregated metrics from the pipeline execution
        """
        logger.info(
            f"Recording metrics to push gateway for {self.entity} - {self.feature_set_name}..."
        )

        self._record_counters(status, pipeline_metrics)
        self._record_duration(status, duration_seconds)

        logger.info(
            f"Metrics recorded - Status: {status}, Duration: {duration_seconds:.2f}s, "
            f"Messages: {pipeline_metrics.total_messages}, Bytes: {pipeline_metrics.total_bytes}"
        )

    def _record_counters(
        self,
        status: str,
        final_metrics: PipelineMetrics,
    ) -> None:
        """Record counter metrics for this execution."""
        attributes = {
            "status": status,
            "feature_set": self.feature_set_name,
            "entity": self.entity,
        }

        self.job_runs_counter.add(1, attributes=attributes)

        self.messages_written_counter.add(
            final_metrics.total_messages,
            attributes=attributes,
        )

        self.message_bytes_written_counter.add(
            final_metrics.total_bytes,
            attributes=attributes,
        )

        for change_type, count in final_metrics.change_type_counts.items():
            self.messages_by_change_type_counter.add(
                count,
                attributes={**attributes, "change_type": change_type},
            )

    def _record_duration(
        self,
        status: str,
        duration_seconds: float,
    ) -> None:
        """Record job duration gauge."""
        self.job_duration_gauge.set(
            duration_seconds,
            attributes={
                "status": status,
                "feature_set": self.feature_set_name,
                "entity": self.entity,
            },
        )

    def flush(self, timeout_seconds: int = 30) -> None:
        """
        Flush metrics and shutdown the provider.

        This method is isolated and will NOT raise exceptions. Metrics are
        "best effort" - failures here should not affect job success status.

        Note: We only call shutdown() here, not force_flush() + shutdown().
        The MeterProvider.shutdown() already performs a final flush internally
        via the PeriodicExportingMetricReader._ticker method before terminating.
        Calling force_flush() before shutdown() would cause duplicate exports.

        Args:
            timeout_seconds: Maximum time to wait for shutdown completion

        Raises:
            None: This method never raises exceptions (best-effort metrics)
        """
        try:
            logger.info("Shutting down metrics provider (includes final flush)...")
            self.meter_provider.shutdown(timeout_millis=timeout_seconds * 1000)
            logger.info("Metrics provider shutdown successfully")

        except TimeoutError:
            logger.warning(
                f"Metrics shutdown timed out after {timeout_seconds}s. "
                "Metrics may be incomplete but job completed successfully."
            )

        except Exception as e:
            logger.warning(
                f"Failed to shutdown metrics provider (non-fatal): {e}. "
                "Job completed successfully but metrics may not have been published.",
                exc_info=True,
            )
