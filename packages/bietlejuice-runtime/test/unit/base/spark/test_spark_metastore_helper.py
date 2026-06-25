"""Unit tests for SparkMetastoreHelper."""

from collections import OrderedDict
from unittest import mock

import pytest

from bietlejuice.base.spark.spark_metastore_helper import SparkMetastoreHelper


@pytest.fixture
def spark_metastore_helper():
    with mock.patch.object(
        SparkMetastoreHelper, "get_metastores_metadata", return_value=("db", "s3://db/")
    ):
        helper = SparkMetastoreHelper("bucket", "clean", "schema", "table", False)
    return helper


class TestGetAllTablesMetadata:
    @mock.patch(
        "bietlejuice.base.spark.spark_metastore_helper.should_skip_emr_hive_partition_sync",
        return_value=True,
    )
    @mock.patch.object(SparkMetastoreHelper, "get_table_names", return_value=["events"])
    def test_skips_show_partitions_for_emr_delta_tables(
        self,
        _mock_table_names,
        _mock_should_skip,
        spark_metastore_helper,
    ):
        spark_metastore_helper.spark_metastore_service = mock.MagicMock()
        spark_metastore_helper.spark_metastore_service.client.conn = mock.MagicMock()
        spark_metastore_helper.spark_metastore_service.get_table_partition_keys.return_value = [
            ("year", "int")
        ]
        spark_metastore_helper.get_spark_metastore_table_columns = mock.MagicMock(
            return_value=OrderedDict([("id", "bigint")])
        )
        spark_metastore_helper.get_spark_metastore_table_partition_values = (
            mock.MagicMock()
        )

        metadata = spark_metastore_helper.get_all_tables_metadata(
            get_partition_values=True
        )

        assert metadata["events"]["partition_values"] == []
        spark_metastore_helper.get_spark_metastore_table_partition_values.assert_not_called()

    @mock.patch(
        "bietlejuice.base.spark.spark_metastore_helper.should_skip_emr_hive_partition_sync",
        return_value=False,
    )
    @mock.patch.object(SparkMetastoreHelper, "get_table_names", return_value=["events"])
    def test_fetches_partition_values_when_not_skipped(
        self,
        _mock_table_names,
        _mock_should_skip,
        spark_metastore_helper,
    ):
        spark_metastore_helper.spark_metastore_service = mock.MagicMock()
        spark_metastore_helper.spark_metastore_service.client.conn = mock.MagicMock()
        spark_metastore_helper.spark_metastore_service.get_table_partition_keys.return_value = [
            ("year", "int")
        ]
        spark_metastore_helper.get_spark_metastore_table_columns = mock.MagicMock(
            return_value=OrderedDict([("id", "bigint")])
        )
        spark_metastore_helper.get_spark_metastore_table_partition_values = (
            mock.MagicMock(return_value=[["2026"]])
        )

        metadata = spark_metastore_helper.get_all_tables_metadata(
            get_partition_values=True
        )

        assert metadata["events"]["partition_values"] == [["2026"]]
        spark_metastore_helper.get_spark_metastore_table_partition_values.assert_called_once_with(
            "events"
        )
