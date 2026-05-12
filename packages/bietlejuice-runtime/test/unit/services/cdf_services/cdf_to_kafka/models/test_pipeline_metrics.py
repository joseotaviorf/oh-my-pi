"""Unit tests for PipelineMetrics dataclass."""

from bietlejuice.services.cdf_services.cdf_to_kafka.models.batch_metrics import (
    BatchMetrics,
)
from bietlejuice.services.cdf_services.cdf_to_kafka.models.pipeline_metrics import (
    PipelineMetrics,
)


class TestPipelineMetricsAddBatch:
    """Tests for PipelineMetrics.add_batch method."""

    def test_adds_first_batch_metrics(self):
        """Test adding the first batch to empty pipeline metrics."""
        pipeline_metrics = PipelineMetrics()

        batch = BatchMetrics(
            batch_id=0,
            change_type_counts={"insert": 10},
            change_type_bytes={"insert": 1000},
            total_records=10,
            total_bytes=1000,
        )

        pipeline_metrics.add_batch(batch)

        assert pipeline_metrics.change_type_counts == {"insert": 10}
        assert pipeline_metrics.change_type_bytes == {"insert": 1000}
        assert pipeline_metrics.total_messages == 10
        assert pipeline_metrics.total_bytes == 1000

    def test_accumulates_multiple_batches_same_change_type(self):
        """Test accumulating multiple batches with same change type."""
        pipeline_metrics = PipelineMetrics()

        batch1 = BatchMetrics(
            batch_id=0,
            change_type_counts={"insert": 10},
            change_type_bytes={"insert": 1000},
            total_records=10,
            total_bytes=1000,
        )

        batch2 = BatchMetrics(
            batch_id=1,
            change_type_counts={"insert": 5},
            change_type_bytes={"insert": 500},
            total_records=5,
            total_bytes=500,
        )

        pipeline_metrics.add_batch(batch1)
        pipeline_metrics.add_batch(batch2)

        assert pipeline_metrics.change_type_counts == {"insert": 15}
        assert pipeline_metrics.change_type_bytes == {"insert": 1500}
        assert pipeline_metrics.total_messages == 15
        assert pipeline_metrics.total_bytes == 1500

    def test_accumulates_different_change_types(self):
        """Test accumulating batches with different change types."""
        pipeline_metrics = PipelineMetrics()

        batch1 = BatchMetrics(
            batch_id=0,
            change_type_counts={"insert": 10},
            change_type_bytes={"insert": 1000},
            total_records=10,
            total_bytes=1000,
        )

        batch2 = BatchMetrics(
            batch_id=1,
            change_type_counts={"update_postimage": 5},
            change_type_bytes={"update_postimage": 500},
            total_records=5,
            total_bytes=500,
        )

        pipeline_metrics.add_batch(batch1)
        pipeline_metrics.add_batch(batch2)

        assert pipeline_metrics.change_type_counts == {
            "insert": 10,
            "update_postimage": 5,
        }
        assert pipeline_metrics.change_type_bytes == {
            "insert": 1000,
            "update_postimage": 500,
        }
        assert pipeline_metrics.total_messages == 15
        assert pipeline_metrics.total_bytes == 1500
