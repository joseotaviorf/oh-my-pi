"""Unit tests for SparkMetastoreHelper."""

from collections import OrderedDict
from unittest import mock

import pytest

from bietlejuice.base.pipeline.layer_enum import LayerEnum
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


class TestSetTimestampsAsString:
    def test_coerces_timestamp_date_decimal_and_binary(self):
        """OpenX reads nested types natively; temporals, decimals, and binary are fragile."""
        cols = OrderedDict(
            [
                ("id", "bigint"),
                ("amount", "decimal(17,2)"),
                ("ts", "timestamp"),
                ("dt", "date"),
                ("tags", "array<string>"),
                ("blob", "binary"),
            ]
        )
        result = SparkMetastoreHelper.set_timestamps_as_string(cols)
        assert result["id"] == "bigint"
        assert result["amount"] == "string"
        assert result["ts"] == "string"
        assert result["dt"] == "string"
        assert result["tags"] == "array<string>"
        assert result["blob"] == "string"

    def test_nested_timestamp_is_not_rewritten(self):
        """A naive substring replace turned ``array<timestamp>`` into
        ``array<string>``; the type-aware coercion leaves the whole type alone.
        """
        cols = OrderedDict([("stamps", "array<timestamp>")])
        result = SparkMetastoreHelper.set_timestamps_as_string(cols)
        assert result["stamps"] == "array<timestamp>"


class TestGetMetastoresMetadataTransformationGrade:
    @mock.patch("bietlejuice.base.spark.spark_metastore_helper.SparkMetastoreService")
    @mock.patch("bietlejuice.base.spark.spark_metastore_helper.SparkClient")
    def test_transformation_resolves_graded_name_and_path(
        self, _mock_client, _mock_service
    ):
        helper = SparkMetastoreHelper(
            "bucket-forno",
            LayerEnum.TRANSFORMATION.value,
            "terminator_test",
            "termination",
            False,
            transformation_grade="clean",
        )

        assert helper.spark_database_name == "transformation_terminator_test_clean"
        assert (
            helper.database_location
            == "s3a://bucket-forno/transformation/terminator_test/clean/"
        )

    @mock.patch("bietlejuice.base.spark.spark_metastore_helper.SparkMetastoreService")
    @mock.patch("bietlejuice.base.spark.spark_metastore_helper.SparkClient")
    def test_clean_layer_is_unchanged_without_grade(self, _mock_client, _mock_service):
        helper = SparkMetastoreHelper(
            "bucket-forno", "clean", "terminator", "termination", False
        )

        assert helper.spark_database_name == "datalake_terminator_clean"
        assert helper.database_location == "s3a://bucket-forno/clean/terminator/"

    @mock.patch("bietlejuice.base.spark.spark_metastore_helper.SparkMetastoreService")
    @mock.patch("bietlejuice.base.spark.spark_metastore_helper.SparkClient")
    def test_transformation_without_grade_raises(self, _mock_client, _mock_service):
        with pytest.raises(ValueError, match="transformation_grade"):
            SparkMetastoreHelper(
                "bucket-forno",
                LayerEnum.TRANSFORMATION.value,
                "terminator_test",
                "termination",
                False,
            )
