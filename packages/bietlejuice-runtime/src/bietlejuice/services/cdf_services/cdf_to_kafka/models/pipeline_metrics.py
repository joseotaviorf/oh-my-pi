from dataclasses import dataclass, field
from typing import Dict

from bietlejuice.services.cdf_services.cdf_to_kafka.models.batch_metrics import (
    BatchMetrics,
)


@dataclass
class PipelineMetrics:
    """Accumulated metrics across all batches."""

    change_type_counts: Dict[str, int] = field(default_factory=dict)
    change_type_bytes: Dict[str, int] = field(default_factory=dict)
    total_messages: int = 0
    total_bytes: int = 0

    def add_batch(self, batch_metrics: BatchMetrics) -> None:
        """Add metrics from a batch to the accumulated totals."""
        for change_type, count in batch_metrics.change_type_counts.items():
            self.change_type_counts[change_type] = (
                self.change_type_counts.get(change_type, 0) + count
            )
        for change_type, size_bytes in batch_metrics.change_type_bytes.items():
            self.change_type_bytes[change_type] = (
                self.change_type_bytes.get(change_type, 0) + size_bytes
            )
        self.total_messages += batch_metrics.total_records
        self.total_bytes += batch_metrics.total_bytes
