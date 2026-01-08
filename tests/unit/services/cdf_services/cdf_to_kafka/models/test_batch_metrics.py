"""Unit tests for BatchMetrics dataclass."""

import pytest

from bietlejuice.services.cdf_services.cdf_to_kafka.models.batch_metrics import (
    BatchMetrics,
)


class TestBatchMetricsFromCountsAndBytes:
    """Tests for BatchMetrics.from_counts_and_bytes class method."""

    def test_handles_empty_dicts(self):
        """Test that empty dicts result in zero totals."""
        result = BatchMetrics.from_counts_and_bytes(
            batch_id=0,
            batch_counts={},
            batch_bytes={},
        )

        assert result.total_records == 0
        assert result.total_bytes == 0
        assert result.change_type_counts == {}
        assert result.change_type_bytes == {}

    @pytest.mark.parametrize(
        "batch_counts,batch_bytes,expected_records,expected_bytes",
        [
            ({"insert": 1}, {"insert": 100}, 1, 100),
            (
                {"insert": 50, "update_postimage": 25},
                {"insert": 5000, "update_postimage": 2500},
                75,
                7500,
            ),
            (
                {"insert": 10, "update_postimage": 5, "delete": 3},
                {"insert": 1000, "update_postimage": 500, "delete": 300},
                18,
                1800,
            ),
        ],
    )
    def test_calculates_totals_and_preserves_change_types(
        self, batch_counts, batch_bytes, expected_records, expected_bytes
    ):
        """Test calculation of totals and preservation of change type data."""
        result = BatchMetrics.from_counts_and_bytes(
            batch_id=42,
            batch_counts=batch_counts,
            batch_bytes=batch_bytes,
        )

        assert result.batch_id == 42
        assert result.total_records == expected_records
        assert result.total_bytes == expected_bytes
        assert result.change_type_counts == batch_counts
        assert result.change_type_bytes == batch_bytes
