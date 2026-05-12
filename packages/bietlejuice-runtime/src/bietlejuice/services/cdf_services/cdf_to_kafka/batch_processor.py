"""Batch processing for CDF to Kafka pipeline."""

import logging
from typing import Any, Dict

from pyspark.sql import DataFrame

from bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_collector import (
    MetricsCollector,
)

logger = logging.getLogger(__name__)


class BatchProcessor:
    """Processes individual batches from CDF stream."""

    def __init__(
        self,
        kafka_options: Dict[str, Any],
        metrics_collector: MetricsCollector,
    ):
        self.kafka_options = kafka_options
        self.metrics_collector = metrics_collector

    def process_batch(self, batch_df: DataFrame, batch_id: int) -> None:
        """
        Process a single batch: write to Kafka first, then collect metrics.

        Order is critical: metrics are only collected AFTER successful write.
        This ensures metrics reflect data actually published to Kafka.

        Args:
            batch_df: DataFrame for the current batch
            batch_id: ID of the current batch
        """
        if batch_df.isEmpty():
            logger.info(f"Batch {batch_id}: empty batch, skipping")
            return

        batch_df.persist()
        try:
            kafka_df = batch_df.drop("_change_type")
            kafka_df.write.format("kafka").options(**self.kafka_options).save()

            self.metrics_collector.collect_batch_metrics(batch_df, batch_id)

        finally:
            batch_df.unpersist()
