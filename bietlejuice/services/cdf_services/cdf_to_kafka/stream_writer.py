"""Kafka stream writer with metrics integration."""

import logging
import os
import time
from typing import Any, Dict, Optional

from pyspark.sql import DataFrame
from pyspark.sql.streaming import StreamingQuery

from bietlejuice.services.cdf_services.cdf_to_kafka.batch_processor import (
    BatchProcessor,
)
from bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_collector import (
    MetricsCollector,
)
from bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher import (
    CDFToKafkaMetricsPublisher,
)

logger = logging.getLogger(__name__)


class KafkaStreamWriter:
    """Manages streaming writes to Kafka with metrics publication."""

    def __init__(
        self,
        checkpoint_location: str,
        kafka_options: Dict[str, Any],
        metrics_publisher: CDFToKafkaMetricsPublisher,
    ):
        self.checkpoint_location = checkpoint_location
        self.kafka_options = kafka_options
        self.metrics_publisher = metrics_publisher

        self.metrics_collector = MetricsCollector()

        self.batch_processor = BatchProcessor(
            kafka_options=kafka_options,
            metrics_collector=self.metrics_collector,
        )

    def write_to_kafka(self, df: DataFrame) -> None:
        """
        Write transformed data to Kafka topic using foreachBatch.

        Args:
            df: Transformed DataFrame ready for Kafka
        """
        start_time = time.time()
        status = "success"
        query: Optional[StreamingQuery] = None

        try:
            query = (
                df.writeStream.foreachBatch(self.batch_processor.process_batch)
                .option("checkpointLocation", self.checkpoint_location)
                .trigger(availableNow=True)
                .start()
            )

            logger.info(
                f"Started streaming to Kafka topic '{self.kafka_options['topic']}'"
            )

            query.awaitTermination()

            if query.exception():
                status = "error"
                raise query.exception()

        except Exception as e:
            status = "error"
            logger.error(f"Error writing to Kafka: {e}", exc_info=True)
            raise

        finally:
            duration = time.time() - start_time

            self._stop_query_safely(query)
            self._publish_metrics_if_enabled(status=status, duration=duration)

    def _stop_query_safely(self, query: Optional[StreamingQuery]) -> None:
        """Stop streaming query without raising exceptions."""
        if not query:
            return

        try:
            if query.isActive:
                query.stop()
                logger.info("Streaming query stopped")
        except Exception as e:
            logger.warning(f"Error stopping query (non-fatal): {e}")

    def _publish_metrics_if_enabled(self, status: str, duration: float) -> None:
        """
        Publish metrics if in production environment.

        Metrics are "best effort". Failures do not affect job status.
        """
        environment = os.environ.get("ENVIRONMENT", "dev")

        if environment != "prod":
            logger.info(f"Skipping metrics in {environment} environment")
            return

        self.metrics_publisher.record_write(
            status=status,
            duration_seconds=duration,
            pipeline_metrics=self.metrics_collector.pipeline_metrics,
        )

        timeout = int(os.environ.get("METRICS_FLUSH_TIMEOUT_SEC", "30"))
        self.metrics_publisher.flush(timeout_seconds=timeout)
