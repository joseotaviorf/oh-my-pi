from unittest import mock

import pytest

from bietlejuice.base.spark.delta_secondary_catalog_sync import (
    partition_columns_present,
    sync_delta_write_to_secondary_catalog,
)


class TestPartitionColumnsPresent:
    def test_filters_to_existing_columns_stable_order(self):
        df = mock.MagicMock()
        df.columns = ["day", "id", "year"]
        assert partition_columns_present(df, ("year", "month", "day")) == [
            "year",
            "day",
        ]


class TestSyncDeltaWriteToSecondaryCatalog:
    @mock.patch(
        "bietlejuice.base.spark.delta_secondary_catalog_sync.CatalogStrategyResolver"
    )
    @mock.patch(
        "bietlejuice.base.spark.delta_secondary_catalog_sync.SchemaService.get_schema_from_dataframe"
    )
    def test_refresh_schema_sync_order(self, mock_get_schema, mock_catalog_resolver):
        spark = mock.MagicMock()
        source_df = mock.MagicMock()
        mock_get_schema.return_value = {"a": "int"}

        sync_delta_write_to_secondary_catalog(
            spark,
            "my_db.my_table",
            "s3://bucket/path/",
            source_df,
            ["year"],
        )

        spark.sql.assert_called_once_with("REFRESH TABLE my_db.my_table")
        mock_get_schema.assert_called_once_with(source_df)
        mock_catalog_resolver.sync_to_secondary_catalog.assert_called_once_with(
            database_name="my_db",
            table_name="my_table",
            table_location="s3://bucket/path/",
            table_schema={"a": "int"},
            partitions=["year"],
            format_str="DELTA",
        )

    def test_invalid_full_table_name_raises(self):
        spark = mock.MagicMock()
        with pytest.raises(ValueError, match="db.table"):
            sync_delta_write_to_secondary_catalog(
                spark, "not_a_two_part_name", "s3://x/", mock.MagicMock(), []
            )
