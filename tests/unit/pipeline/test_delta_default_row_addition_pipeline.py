import pytest
from unittest import mock
from bietlejuice.pipeline.delta_default_row_addition_pipeline import (
    DeltaDefaultRowAdditionPipeline,
)


class TestDeltaDefaultRowAdditionPipeline:
    @pytest.fixture(autouse=True)
    def mock_delta_loader(self):
        with mock.patch(
            "bietlejuice.pipeline.delta_default_row_addition_pipeline.DeltaLoader"
        ) as delta_loader:
            yield delta_loader

    @pytest.fixture(autouse=True)
    def mock_base_spark_context(self):
        with mock.patch(
            "bietlejuice.pipeline.delta_default_row_addition_pipeline.BaseSparkContext"
        ) as base_spark_context:
            yield base_spark_context

    def test_should_do_nothing_for_tables_without_dim_prefix(
        self, mock_delta_loader, mock_base_spark_context
    ):
        # Arrange
        database_name = "dw_foo"
        table_name = "fact_foo"
        database_location = "s3://foo/bar"
        pipeline = DeltaDefaultRowAdditionPipeline(
            database_name, table_name, database_location
        )

        # Act
        pipeline.run()

        # Assert
        assert not mock_base_spark_context.spark.called
        assert not mock_delta_loader.called

    def test_should_merge_default_row_into_dim_table(
        self, mock_delta_loader, mock_base_spark_context
    ):
        # Arrange
        mock_schema = [mock.Mock()]
        mock_schema[0].name = "sk_test"
        mock_base_spark_context.spark.table.return_value.schema = mock_schema
        mock_df = mock.Mock(columns=["sk_test"])
        mock_base_spark_context.spark.createDataFrame.return_value = mock_df

        database_name = "dw_foo"
        table_name = "dim_foo"
        database_location = "s3://foo/bar"
        pipeline = DeltaDefaultRowAdditionPipeline(
            database_name,
            table_name,
            database_location,
            spark=mock_base_spark_context.spark,
        )

        # Act
        pipeline.run()

        # Assert
        mock_base_spark_context.spark.createDataFrame.assert_called_once_with(
            data=[{"sk_test": -1}], schema=mock_schema
        )
        mock_delta_loader.return_value.load_table.assert_called_once_with(
            table_name="dw_foo.dim_foo",
            path="s3://foo/bar/dim_foo",
            source_df=mock_df,
            merge_on=["sk_test"],
            when_matched_update_condition="FALSE",
        )
