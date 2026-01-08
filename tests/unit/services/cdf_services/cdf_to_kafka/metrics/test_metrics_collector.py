"""Unit tests for MetricsCollector."""

from pyspark.sql.types import ArrayType, BinaryType, StringType, StructField, StructType

from bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_collector import (
    MetricsCollector,
)
from bietlejuice.services.cdf_services.cdf_to_kafka.models.batch_metrics import (
    BatchMetrics,
)

HEADERS_SCHEMA = ArrayType(
    StructType(
        [
            StructField("key", StringType(), nullable=False),
            StructField("value", BinaryType(), nullable=True),
        ]
    )
)

KAFKA_MESSAGE_SCHEMA = StructType(
    [
        StructField("key", StringType(), nullable=False),
        StructField("value", BinaryType(), nullable=False),
        StructField("headers", HEADERS_SCHEMA, nullable=False),
    ]
)

KAFKA_MESSAGE_WITH_CHANGE_TYPE_SCHEMA = StructType(
    [
        StructField("key", StringType(), nullable=False),
        StructField("value", BinaryType(), nullable=False),
        StructField("headers", HEADERS_SCHEMA, nullable=False),
        StructField("_change_type", StringType(), nullable=False),
    ]
)


class TestMetricsCollectorCalculateMessageSizes:
    """Tests for MetricsCollector._calculate_message_sizes method."""

    def test_calculates_correct_size_for_simple_message(self, spark_session):
        """Test message size calculation for a simple message."""
        collector = MetricsCollector()

        key = '{"id": 1}'
        value = bytearray(b'{"name": "Alice"}')
        data = [(key, value, [])]
        df = spark_session.createDataFrame(data, KAFKA_MESSAGE_SCHEMA)

        result = collector._calculate_message_sizes(df)
        row = result.collect()[0]

        expected_size = len(key.encode("utf-8")) + len(value)
        assert "_message_size" in result.columns
        assert row["_message_size"] == expected_size


class TestMetricsCollectorAggregateMetrics:
    """Tests for MetricsCollector._aggregate_metrics_by_change_type method."""

    def test_aggregates_by_change_type(self, spark_session):
        """Test aggregation by change type."""
        collector = MetricsCollector()

        data = [
            ("insert", 100),
            ("insert", 150),
            ("update_postimage", 200),
        ]
        df = spark_session.createDataFrame(data, ["_change_type", "_message_size"])

        result = collector._aggregate_metrics_by_change_type(df)

        result_dict = {row["_change_type"]: row for row in result}
        assert result_dict["insert"]["count"] == 2
        assert result_dict["insert"]["total_bytes"] == 250
        assert result_dict["update_postimage"]["count"] == 1
        assert result_dict["update_postimage"]["total_bytes"] == 200


class TestMetricsCollectorCollectBatchMetrics:
    """Tests for MetricsCollector.collect_batch_metrics method."""

    def test_returns_batch_metrics_and_accumulates_in_pipeline(self, spark_session):
        """Test that batch metrics are returned and accumulated in pipeline_metrics."""
        collector = MetricsCollector()

        data = [
            ('{"id": 1}', bytearray(b'{"name": "Alice"}'), [], "insert"),
            ('{"id": 2}', bytearray(b'{"name": "Bob"}'), [], "insert"),
            ('{"id": 3}', bytearray(b'{"name": "Charlie"}'), [], "update_postimage"),
        ]
        df = spark_session.createDataFrame(data, KAFKA_MESSAGE_WITH_CHANGE_TYPE_SCHEMA)

        result = collector.collect_batch_metrics(df, batch_id=1)

        assert isinstance(result, BatchMetrics)
        assert result.batch_id == 1
        assert result.total_records == 3
        assert result.change_type_counts["insert"] == 2
        assert result.change_type_counts["update_postimage"] == 1
        assert collector.pipeline_metrics.total_messages == 3
