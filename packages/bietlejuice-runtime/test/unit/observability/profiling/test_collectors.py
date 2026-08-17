from unittest import mock

from bietlejuice.observability.profiling.collectors import (
    collect_partition_metrics,
    collect_table_metrics,
    compute_schema_hash,
)
from bietlejuice.observability.profiling.constants import CollectionMethod


class TestComputeSchemaHash:
    def test_stable_fingerprint_changes_on_drift(self):
        fields = [{"name": "id", "type": "bigint"}, {"name": "ts", "type": "timestamp"}]
        assert compute_schema_hash(fields) == compute_schema_hash(list(fields))
        assert compute_schema_hash([{"name": "id", "type": "bigint"}]) != (
            compute_schema_hash([{"name": "id", "type": "string"}])
        )


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
        reader.row_count_from_log.return_value = (1000, True)
        reader.latest_partition_with_data_from_log.return_value = (
            "year=2026/month=07/day=22"
        )
        return reader

    def test_maps_detail_and_log_row_count(self):
        reader = self._reader()

        metrics = collect_table_metrics(reader, "dw_rent", "fact_contracts")

        assert metrics["row_count"] == 1000
        assert metrics["collection_method"] == CollectionMethod.SPARK_LOG.value
        assert metrics["num_files"] == 12
        assert metrics["size_bytes"] == 2048
        assert metrics["num_columns"] == 2
        assert metrics["partition_columns"] == ["year", "month", "day"]
        # Latest with data — not the run-day partition (SLA lives at partition grain).
        assert metrics["latest_partition_value"] == "year=2026/month=07/day=22"
        assert metrics["table_features"] == ["deletionVectors"]
        assert len(metrics["schema_hash"]) == 64
        reader.row_count_from_log.assert_called_once_with("dw_rent.fact_contracts")
        reader.latest_partition_with_data_from_log.assert_called_once_with(
            "dw_rent.fact_contracts", ["year", "month", "day"]
        )
        reader.count.assert_not_called()

    def test_falls_back_to_count_when_log_stats_incomplete(self):
        reader = self._reader()
        reader.row_count_from_log.return_value = (None, False)
        reader.count.return_value = 500

        metrics = collect_table_metrics(reader, "dw_rent", "fact_contracts")

        assert metrics["row_count"] == 500
        assert (
            metrics["collection_method"] == CollectionMethod.SPARK_COUNT_FALLBACK.value
        )
        reader.count.assert_called_once_with("dw_rent.fact_contracts")


class TestCollectPartitionMetrics:
    def test_returns_empty_when_unpartitioned(self):
        reader = mock.MagicMock()
        assert (
            collect_partition_metrics(
                reader, "dw_rent", "dim_user", [], None, "2026-07-23"
            )
            == []
        )

    def test_profiles_run_day_inventory_independent_of_rows_written(self):
        """SLA uses inventory (row_count); rows_written is commit context only."""
        reader = mock.MagicMock()
        reader.partition_row_count_from_log.return_value = (1000, True)
        last_commit = {"operationMetrics": {"numOutputRows": "0"}}

        result = collect_partition_metrics(
            reader,
            "dw_rent",
            "fact_contracts",
            ["year", "month", "day"],
            last_commit,
            "2026-07-23",
        )

        assert len(result) == 1
        record = result[0]
        assert record["row_count"] == 1000
        assert record["rows_written"] == 0
        assert record["collection_method"] == CollectionMethod.SPARK_LOG.value
        assert record["partition_key"] == [
            {"name": "year", "value": "2026"},
            {"name": "month", "value": "07"},
            {"name": "day", "value": "23"},
        ]
        reader.count.assert_not_called()

    def test_rows_written_none_when_commit_missing(self):
        reader = mock.MagicMock()
        reader.partition_row_count_from_log.return_value = (5, True)

        result = collect_partition_metrics(
            reader,
            "dw_rent",
            "fact_contracts",
            ["year", "month", "day"],
            None,
            "2026-07-23",
        )

        assert result[0]["rows_written"] is None

    def test_falls_back_to_count_when_log_stats_incomplete(self):
        reader = mock.MagicMock()
        reader.partition_row_count_from_log.return_value = (None, False)
        reader.count.return_value = 17

        result = collect_partition_metrics(
            reader,
            "dw_rent",
            "fact_contracts",
            ["year", "month", "day"],
            None,
            "2026-07-23",
        )

        assert result[0]["row_count"] == 17
        assert (
            result[0]["collection_method"]
            == CollectionMethod.SPARK_COUNT_FALLBACK.value
        )
        reader.count.assert_called_once_with(
            "dw_rent.fact_contracts",
            "`year` = '2026' AND `month` = '07' AND `day` = '23'",
        )

    def test_skips_non_standard_partition_columns(self):
        reader = mock.MagicMock()
        assert (
            collect_partition_metrics(
                reader,
                "dw_rent",
                "fact_contracts",
                ["dt"],
                None,
                "2026-07-23",
            )
            == []
        )
        reader.partition_row_count_from_log.assert_not_called()
