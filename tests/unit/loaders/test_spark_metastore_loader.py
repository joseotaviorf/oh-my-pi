from collections import OrderedDict

import pytest
from mock import patch

from bietlejuice.services.schema_service import SchemaService


class TestSparkMetastoreLoader:
    @pytest.fixture(autouse=True)
    def unity_catalog_helper(self):
        with patch(
            "bietlejuice.loaders.spark_metastore_loader.UnityCatalogHelper"
        ) as unity_catalog_helper:
            yield unity_catalog_helper

    @pytest.mark.parametrize(
        "format_options, mode, database_name, table_name, database_location",
        [
            ("parquet", "append", "", "test", "local/path"),
            ("csv", "overwrite", "house", "real", "s3://path"),
        ],
    )
    @patch.object(SchemaService, "get_schema_from_dataframe")
    def test_update_metastore(
        self,
        mocked_schema_service,
        format_options,
        mode,
        database_name,
        table_name,
        database_location,
        mocked_write_df,
        metastore_loader,
    ):
        # given
        s3_path = database_location + table_name
        partitions = []
        df_schema = OrderedDict({"col": "string"})

        mocked_schema_service.return_value = df_schema
        metastore_loader.schema_service.get_schema_from_dataframe = (
            mocked_schema_service
        )

        # when
        metastore_loader.update_metastore(
            df=mocked_write_df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
        )

        # then
        metastore_loader.metastore_service.create_external_table.assert_called_with(
            database_name, table_name, s3_path, df_schema, partitions, format_options
        )

    @pytest.mark.parametrize(
        "database_name, table_name, format_options, database_location",
        [
            (None, "table", None, None),
            ("database", None, None, None),
            ("database", 123, None, None),
        ],
    )
    def test_update_metastore_with_invalid_params(
        self,
        database_name,
        table_name,
        format_options,
        database_location,
        mocked_write_df,
        metastore_loader,
    ):
        # act and assert
        with pytest.raises(ValueError):
            metastore_loader.update_metastore(
                mocked_write_df,
                database_name,
                table_name,
                format_options,
                database_location,
            )

    def test_update_metastore_with_invalid_df(self, metastore_loader):
        # arrange
        database_name = "default"
        table_name = "test_table"
        format_options = "overwrite"
        database_location = "path/to/file"

        df = None

        with pytest.raises(ValueError):
            metastore_loader.update_metastore(
                df=df,
                database_name=database_name,
                table_name=table_name,
                format_options=format_options,
                database_location=database_location,
            )

    @pytest.mark.parametrize(
        "format_options, mode, database_name, table_name, database_location",
        [
            ("parquet", "append", "", "test", "local/path"),
            ("csv", "overwrite", "house", "real", "s3://path"),
        ],
    )
    @patch.object(SchemaService, "get_schema_from_dataframe")
    def test_update_metastore_should_not_sync_if_uc_is_not_enabled(
        self,
        mocked_schema_service,
        format_options,
        mode,
        database_name,
        table_name,
        database_location,
        mocked_write_df,
        metastore_loader,
        unity_catalog_helper,
    ):
        # given
        df_schema = OrderedDict({"col": "string"})

        mocked_schema_service.return_value = df_schema
        metastore_loader.schema_service.get_schema_from_dataframe = (
            mocked_schema_service
        )
        unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = False
        unity_catalog_helper.is_default_catalog_using_unity.return_value = False

        # when
        metastore_loader.update_metastore(
            df=mocked_write_df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
        )

        # then
        unity_catalog_helper.sync_table_to_unity_catalog.assert_not_called()

    @pytest.mark.parametrize(
        "format_options, mode, database_name, table_name, database_location",
        [
            ("parquet", "append", "", "test", "local/path"),
            ("csv", "overwrite", "house", "real", "s3://path"),
        ],
    )
    @patch.object(SchemaService, "get_schema_from_dataframe")
    def test_update_metastore_should_not_sync_if_uc_is_enabled_but_table_is_saved_directly_to_uc(
        self,
        mocked_schema_service,
        format_options,
        mode,
        database_name,
        table_name,
        database_location,
        mocked_write_df,
        metastore_loader,
        unity_catalog_helper,
    ):
        # given
        df_schema = OrderedDict({"col": "string"})

        mocked_schema_service.return_value = df_schema
        metastore_loader.schema_service.get_schema_from_dataframe = (
            mocked_schema_service
        )
        unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = True
        unity_catalog_helper.is_default_catalog_using_unity.return_value = True

        # when
        metastore_loader.update_metastore(
            df=mocked_write_df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
        )

        # then
        unity_catalog_helper.sync_table_to_unity_catalog.assert_not_called()

    @pytest.mark.parametrize(
        "format_options, mode, database_name, table_name, database_location",
        [
            ("parquet", "append", "", "test", "local/path"),
            ("csv", "overwrite", "house", "real", "s3://path"),
        ],
    )
    @patch.object(SchemaService, "get_schema_from_dataframe")
    def test_update_metastore_should_not_sync_if_uc_enabled_but_partitioned(
        self,
        mocked_schema_service,
        format_options,
        mode,
        database_name,
        table_name,
        database_location,
        mocked_write_df,
        metastore_loader,
        unity_catalog_helper,
    ):
        # given
        df_schema = OrderedDict({"col": "string"})

        mocked_schema_service.return_value = df_schema
        metastore_loader.schema_service.get_schema_from_dataframe = (
            mocked_schema_service
        )
        unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = True
        unity_catalog_helper.is_default_catalog_using_unity.return_value = False

        # when
        metastore_loader.update_metastore(
            df=mocked_write_df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
            partitions=["year", "month", "day"],
        )

        # then
        unity_catalog_helper.sync_table_to_unity_catalog.assert_not_called()

    @pytest.mark.parametrize(
        "format_options, mode, database_name, table_name, database_location",
        [
            ("parquet", "append", "", "test", "local/path"),
            ("csv", "overwrite", "house", "real", "s3://path"),
        ],
    )
    @patch.object(SchemaService, "get_schema_from_dataframe")
    def test_update_metastore_should_sync_if_uc_enabled_and_table_is_not_partitioned(
        self,
        mocked_schema_service,
        format_options,
        mode,
        database_name,
        table_name,
        database_location,
        mocked_write_df,
        metastore_loader,
        unity_catalog_helper,
    ):
        # given
        df_schema = OrderedDict({"col": "string"})

        mocked_schema_service.return_value = df_schema
        metastore_loader.schema_service.get_schema_from_dataframe = (
            mocked_schema_service
        )
        unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = True
        unity_catalog_helper.is_default_catalog_using_unity.return_value = False

        # when
        metastore_loader.update_metastore(
            df=mocked_write_df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
        )

        # then
        unity_catalog_helper.sync_table_to_unity_catalog.assert_called_once_with(
            f"{database_name}.{table_name}"
        )
