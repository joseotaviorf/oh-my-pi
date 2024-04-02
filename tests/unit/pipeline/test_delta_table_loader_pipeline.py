import pytest
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
    def mock_spark_metastore_service(self):
        with mock.patch(
            "bietlejuice.pipeline.delta_table_loader_pipeline.SparkMetastoreService"
        ) as spark_metastore_service:
            yield spark_metastore_service

    def test_load_and_register(self, mock_delta_loader, mock_spark_metastore_service):
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
        )
        mock_spark_metastore_service.assert_called_once()
        mock_spark_metastore_service.return_value.refresh_table.assert_called_once()
