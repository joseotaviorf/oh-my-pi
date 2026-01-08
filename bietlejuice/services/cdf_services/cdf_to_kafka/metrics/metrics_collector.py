"""Metrics collection and aggregation for CDF to Kafka pipeline."""

import logging
from collections import defaultdict
from typing import Dict, List, Tuple

from pyspark.sql import DataFrame
from pyspark.sql import functions as F

from bietlejuice.services.cdf_services.cdf_to_kafka.models.batch_metrics import (
    BatchMetrics,
)
from bietlejuice.services.cdf_services.cdf_to_kafka.models.pipeline_metrics import (
    PipelineMetrics,
)

logger = logging.getLogger(__name__)


class MetricsCollector:
    """Collects and aggregates metrics from CDF to Kafka batches."""

    def __init__(self):
        self.pipeline_metrics = PipelineMetrics(change_type_counts=defaultdict(int))

    def _calculate_message_sizes(self, batch_df: DataFrame) -> DataFrame:
        """
        Calculate the size of each message in bytes by summing the sizes of key, value, and headers.

        Args:
            batch_df: DataFrame containing Kafka messages

        Returns:
            DataFrame with additional _message_size column
        """
        return batch_df.withColumn(
            "_message_size",
            # 1. Size of the key (string JSON → binary)
            F.coalesce(F.length(F.col("key").cast("binary")), F.lit(0))
            # 2. Size of the value (already binary)
            + F.coalesce(F.length(F.col("value")), F.lit(0))
            # 3. Size of the headers (sum of each header.key + header.value)
            + F.coalesce(
                F.aggregate(
                    F.col("headers"),
                    F.lit(0),
                    lambda acc, header: acc
                    + F.length(header.key.cast("binary"))
                    + F.length(header.value),
                ),
                F.lit(0),
            ),
        )

    def _aggregate_metrics_by_change_type(self, df_with_size: DataFrame) -> List:
        """
        Aggregate metrics by change type to get count and total bytes.

        Args:
            df_with_size: DataFrame with _message_size column

        Returns:
            List of Row objects with _change_type, count, and total_bytes
        """
        return (
            df_with_size.groupBy("_change_type")
            .agg(
                F.count("*").alias("count"),
                F.sum("_message_size").alias("total_bytes"),
            )
            .collect()
        )

    def _process_metrics_results(self, metrics_df: List) -> Tuple[Dict, Dict]:
        """
        Process aggregated metrics results into dictionaries.

        Args:
            metrics_df: List of Row objects with _change_type, count, and total_bytes

        Returns:
            Tuple of (batch_counts, batch_bytes) dictionaries
        """
        batch_counts = {}
        batch_bytes = {}

        for row in metrics_df:
            count = row["count"]
            size_bytes = row["total_bytes"]

            change_type = row["_change_type"]
            batch_counts[change_type] = count
            batch_bytes[change_type] = size_bytes

        return batch_counts, batch_bytes

    def _log_batch_metrics(self, batch_metrics: BatchMetrics) -> None:
        """
        Log the collected batch metrics.

        Args:
            batch_metrics: BatchMetrics object to log
        """
        logger.info(
            f"Batch {batch_metrics.batch_id}: {batch_metrics.total_records} records "
            f"({batch_metrics.total_bytes:,} bytes, "
            f"Change types: {batch_metrics.change_type_counts}"
        )

    def collect_batch_metrics(self, batch_df: DataFrame, batch_id: int) -> BatchMetrics:
        """
        Collect metrics from a batch DataFrame.

        Args:
            batch_df: DataFrame for the current batch
            batch_id: ID of the current batch

        Returns:
            BatchMetrics with change_type counts for this batch
        """
        df_with_size = self._calculate_message_sizes(batch_df)

        metrics_df = self._aggregate_metrics_by_change_type(df_with_size)

        batch_counts, batch_bytes = self._process_metrics_results(metrics_df)

        batch_metrics = BatchMetrics.from_counts_and_bytes(
            batch_id, batch_counts, batch_bytes
        )

        self.pipeline_metrics.add_batch(batch_metrics)

        self._log_batch_metrics(batch_metrics)

        return batch_metrics
