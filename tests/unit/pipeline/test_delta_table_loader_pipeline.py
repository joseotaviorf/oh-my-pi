import pytest
from collections import OrderedDict
from unittest import mock

from bietlejuice.pipeline.delta_table_loader_pipeline import DeltaTableLoaderPipeline


class TestDeltaTableLoaderPipeline:
    @pytest.fixture(autouse=True)
    def mock_delta_loader(self):
        with mock.patch(
            "bietlejuice.pipeline.delta_table_loader_pipeline.DeltaLoader"
        ) as delta_loader:
            yield delta_loader

    @pytest.fixture(autouse=True)
    def mock_loader_metastore_service(self):
        with mock.patch(
            "bietlejuice.pipeline.delta_table_loader_pipeline.MetastoreServiceFactory.create_loader_metastore_service",
            return_value=mock.MagicMock(),
        ) as factory_mock:
            yield factory_mock

    @pytest.fixture(autouse=True)
    def mock_schema_from_dataframe(self):
        with mock.patch(
            "bietlejuice.pipeline.delta_table_loader_pipeline.SchemaService.get_schema_from_dataframe",
            return_value=OrderedDict([("id", "bigint")]),
        ) as p:
            yield p

    @pytest.fixture(autouse=True)
    def mock_sync_to_secondary_catalog(self):
        with mock.patch(
            "bietlejuice.pipeline.delta_table_loader_pipeline.CatalogStrategyResolver.sync_to_secondary_catalog"
        ) as p:
            yield p

    def test_load_and_register(
        self,
        mock_delta_loader,
        mock_loader_metastore_service,
        mock_schema_from_dataframe,
        mock_sync_to_secondary_catalog,
    ):
        # Arrange
        delta_table_loader_pipeline = DeltaTableLoaderPipeline(
            database_name="database_name",
            table_name="table_name",
            database_location="s3://bucket/database_name/",
            layer="layer",
            query="SELECT * FROM table_name",
            partitions=["partition_col"],
            query_template_params={"param1": "value1"},
            merge_schema=True,
            merge_on=["merge_col"],
            when_not_matched_insert_condition="when_not_matched_insert_condition",
            when_matched_update_condition="when_matched_update_condition",
            when_matched_delete_condition="when_matched_delete_condition",
            when_not_matched_by_source_delete_condition="when_not_matched_by_source_delete_condition",
        )
        df = "df"
        format_options = "format_options"

        # Act
        delta_table_loader_pipeline.load_and_register(df, format_options)

        # Assert
        mock_delta_loader.assert_called_once()
        mock_delta_loader.return_value.load_table.assert_called_once_with(
            table_name="database_name.table_name",
            path="s3://bucket/database_name/table_name",
            source_df=df,
            partition_by=["partition_col"],
            merge_schema=True,
            merge_on=["merge_col"],
            when_not_matched_insert_condition="when_not_matched_insert_condition",
            when_matched_update_condition="when_matched_update_condition",
            when_matched_delete_condition="when_matched_delete_condition",
            when_not_matched_by_source_delete_condition="when_not_matched_by_source_delete_condition",
            when_matched_operation=None,
            when_not_matched_operation=None,
            column_mapping_mode=None,
        )
        mock_loader_metastore_service.assert_called_once()
        mock_loader_metastore_service.return_value.refresh_table.assert_called_once()

        mock_schema_from_dataframe.assert_called_once_with(df)
        mock_sync_to_secondary_catalog.assert_called_once_with(
            database_name="database_name",
            table_name="table_name",
            table_location="s3://bucket/database_name/table_name",
            table_schema=OrderedDict([("id", "bigint")]),
            partitions=["partition_col"],
            format_str="DELTA",
        )

    def test_load_and_register_with_column_mapping_mode(
        self,
        mock_delta_loader,
        mock_loader_metastore_service,
        mock_schema_from_dataframe,
        mock_sync_to_secondary_catalog,
    ):
        delta_table_loader_pipeline = DeltaTableLoaderPipeline(
            database_name="database_name",
            table_name="table_name",
            database_location="s3://bucket/database_name/",
            layer="layer",
            query="SELECT * FROM table_name",
            column_mapping_mode="name",
        )
        df = "df"
        format_options = "format_options"

        delta_table_loader_pipeline.load_and_register(df, format_options)

        mock_delta_loader.return_value.load_table.assert_called_once_with(
            table_name="database_name.table_name",
            path="s3://bucket/database_name/table_name",
            source_df=df,
            partition_by=[],
            merge_schema=True,
            merge_on=None,
            when_not_matched_insert_condition=None,
            when_matched_update_condition=None,
            when_matched_delete_condition=None,
            when_not_matched_by_source_delete_condition=None,
            when_matched_operation=None,
            when_not_matched_operation=None,
            column_mapping_mode="name",
        )
