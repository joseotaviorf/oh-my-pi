from dataclasses import dataclass
from typing import Dict


@dataclass
class BatchMetrics:
    """Metrics collected from a single batch."""

    batch_id: int
    change_type_counts: Dict[str, int]
    change_type_bytes: Dict[str, int]
    total_records: int
    total_bytes: int

    @classmethod
    def from_counts_and_bytes(
        cls, batch_id: int, batch_counts: Dict[str, int], batch_bytes: Dict[str, int]
    ) -> "BatchMetrics":
        """
        Create a BatchMetrics object from processed counts and bytes.

        Args:
            batch_id: ID of the current batch
            batch_counts: Dictionary mapping change_type to record counts
            batch_bytes: Dictionary mapping change_type to total bytes

        Returns:
            BatchMetrics object with calculated totals
        """
        total_count = sum(batch_counts.values())
        total_bytes = sum(batch_bytes.values())

        return cls(
            batch_id=batch_id,
            change_type_counts=batch_counts,
            change_type_bytes=batch_bytes,
            total_records=total_count,
            total_bytes=total_bytes,
        )
