from unittest import mock

from bietlejuice.observability.profiling.delta_metadata_reader import (
    DeltaMetadataReader,
)


class TestPartitionSpecs:
    def test_prefers_show_partitions(self):
        # Arrange
        spark = mock.MagicMock()
        spark.sql.return_value.collect.return_value = [
            ("year=2026/month=07/day=23",),
        ]
        reader = DeltaMetadataReader(spark)

        # Act
        specs = reader.partition_specs("db.t", ["year", "month", "day"])

        # Assert
        assert specs == ["year=2026/month=07/day=23"]
        spark.sql.assert_called_once_with("SHOW PARTITIONS db.t")

    def test_falls_back_to_distinct_when_show_partitions_unsupported(self):
        # Arrange — EMR Delta rejects Hive partition management
        spark = mock.MagicMock()
        show = mock.MagicMock()
        show.collect.side_effect = RuntimeError(
            "INVALID_PARTITION_OPERATION.PARTITION_MANAGEMENT_IS_UNSUPPORTED"
        )
        distinct = mock.MagicMock()
        distinct.collect.return_value = [(2026, 7, 26), (2026, 7, 25)]
        spark.sql.side_effect = [show, distinct]
        reader = DeltaMetadataReader(spark)

        # Act
        specs = reader.partition_specs("db.t", ["year", "month", "day"])

        # Assert
        assert specs == [
            "year=2026/month=07/day=26",
            "year=2026/month=07/day=25",
        ]
        assert spark.sql.call_args_list[1].args[0] == (
            "SELECT DISTINCT `year`, `month`, `day` FROM db.t"
        )

    def test_returns_empty_when_show_fails_and_no_columns(self):
        # Arrange
        spark = mock.MagicMock()
        spark.sql.return_value.collect.side_effect = RuntimeError("unsupported")
        reader = DeltaMetadataReader(spark)

        # Act / Assert
        assert reader.partition_specs("db.t") == []
