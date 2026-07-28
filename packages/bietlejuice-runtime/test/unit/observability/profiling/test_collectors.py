from unittest import mock

from bietlejuice.observability.profiling.collectors import (
    collect_partition_metrics,
    collect_table_metrics,
    compute_schema_hash,
)


class TestComputeSchemaHash:
    def test_is_deterministic(self):
        # Arrange
        fields = [{"name": "id", "type": "bigint"}, {"name": "ts", "type": "timestamp"}]

        # Act / Assert
        assert compute_schema_hash(fields) == compute_schema_hash(list(fields))

    def test_changes_on_drift(self):
        # Arrange
        before = [{"name": "id", "type": "bigint"}]
        after = [{"name": "id", "type": "string"}]

        # Act / Assert
        assert compute_schema_hash(before) != compute_schema_hash(after)


class TestCollectTableMetrics:
    def _reader(self):
        reader = mock.MagicMock()
        reader.detail.return_value = {
            "numFiles": 12,
            "sizeInBytes": 2048,
            "createdAt": "2026-01-01",
            "lastModified": "2026-07-23",
            "partitionColumns": ["year", "month", "day"],
            "clusteringColumns": [],
            "properties": {"delta.enableDeletionVectors": "true"},
            "tableFeatures": ["deletionVectors"],
        }
        reader.schema_fields.return_value = [
            {"name": "id", "type": "bigint"},
            {"name": "amount", "type": "double"},
        ]
        reader.count.return_value = 1000
        reader.partition_specs.return_value = [
            "year=2026/month=07/day=22",
            "year=2026/month=07/day=23",
        ]
        return reader

    def test_maps_detail_and_derived_fields(self):
        # Arrange
        reader = self._reader()

        # Act
        metrics = collect_table_metrics(reader, "dw_rent", "fact_contracts")

        # Assert
        assert metrics["row_count"] == 1000
        assert metrics["num_files"] == 12
        assert metrics["size_bytes"] == 2048
        assert metrics["num_columns"] == 2
        assert metrics["partition_columns"] == ["year", "month", "day"]
        assert metrics["latest_partition_value"] == "year=2026/month=07/day=23"
        assert metrics["table_features"] == ["deletionVectors"]
        assert len(metrics["schema_hash"]) == 64  # sha256 hex digest
        reader.count.assert_called_once_with("dw_rent.fact_contracts")
        reader.partition_specs.assert_called_once_with(
            "dw_rent.fact_contracts", ["year", "month", "day"]
        )

    def test_keeps_table_metrics_when_partition_listing_fails(self):
        # Arrange — EMR Delta often rejects SHOW PARTITIONS; reader may raise
        reader = self._reader()
        reader.partition_specs.side_effect = RuntimeError(
            "INVALID_PARTITION_OPERATION.PARTITION_MANAGEMENT_IS_UNSUPPORTED"
        )

        # Act
        metrics = collect_table_metrics(reader, "dw_rent", "fact_contracts")

        # Assert — structural metrics survive; latest partition soft-skipped
        assert metrics["row_count"] == 1000
        assert metrics["schema_hash"]
        assert metrics["latest_partition_value"] is None


class TestCollectPartitionMetrics:
    def test_returns_empty_when_unpartitioned(self):
        # Arrange
        reader = mock.MagicMock()

        # Act
        result = collect_partition_metrics(reader, "dw_rent", "dim_user", [], None)

        # Assert
        assert result == []

    def test_profiles_latest_partition_with_rows_written(self):
        # Arrange
        reader = mock.MagicMock()
        reader.partition_specs.return_value = [
            "year=2026/month=07/day=22",
            "year=2026/month=07/day=23",
        ]
        reader.count.return_value = 42
        last_commit = {"operationMetrics": {"numOutputRows": "42"}}

        # Act
        result = collect_partition_metrics(
            reader, "dw_rent", "fact_contracts", ["year", "month", "day"], last_commit
        )

        # Assert
        assert len(result) == 1
        record = result[0]
        assert record["row_count"] == 42
        assert record["rows_written"] == 42
        assert record["partition_key"] == [
            {"name": "year", "value": "2026"},
            {"name": "month", "value": "07"},
            {"name": "day", "value": "23"},
        ]
        reader.count.assert_called_once_with(
            "dw_rent.fact_contracts",
            "`year` = '2026' AND `month` = '07' AND `day` = '23'",
        )

    def test_rows_written_none_when_commit_missing(self):
        # Arrange
        reader = mock.MagicMock()
        reader.partition_specs.return_value = ["year=2026/month=07/day=23"]
        reader.count.return_value = 5

        # Act
        result = collect_partition_metrics(
            reader, "dw_rent", "fact_contracts", ["year", "month", "day"], None
        )

        # Assert
        assert result[0]["rows_written"] is None

    def test_picks_latest_partition_chronologically_not_lexicographically(self):
        # Arrange — month=9 must beat month=12 lexicographically but lose chronologically
        reader = mock.MagicMock()
        reader.partition_specs.return_value = [
            "year=2026/month=9/day=15",
            "year=2026/month=12/day=01",
        ]
        reader.count.return_value = 10

        # Act
        result = collect_partition_metrics(
            reader, "dw_rent", "fact_contracts", ["year", "month", "day"], None
        )

        # Assert
        assert result[0]["partition_key"] == [
            {"name": "year", "value": "2026"},
            {"name": "month", "value": "12"},
            {"name": "day", "value": "01"},
        ]
