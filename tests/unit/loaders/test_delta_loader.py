import pytest
from unittest import mock
from bietlejuice.loaders.delta_loader import DeltaLoader
from py4j.protocol import Py4JJavaError
from pyspark.sql.utils import AnalysisException


class TestDeltaLoader:
    @pytest.fixture
    def delta_table_builder_mock(self):
        builder = mock.MagicMock()
        builder.tableName.return_value = builder
        builder.addColumns.return_value = builder
        builder.partitionedBy.return_value = builder
        builder.location.return_value = builder
        return builder

    @pytest.fixture
    def merge_builder_mock(self):
        builder = mock.MagicMock()
        builder.whenMatchedDelete.return_value = builder
        builder.whenMatchedUpdateAll.return_value = builder
        builder.whenNotMatchedInsertAll.return_value = builder
        return builder

    @pytest.fixture
    def mock_target_df(self, merge_builder_mock):
        target_df = mock.MagicMock()
        target_df.schema = ["column1", "column2"]
        target_df.alias.return_value = target_df
        target_df.merge.return_value = merge_builder_mock
        return target_df

    @pytest.fixture
    def mock_delta_table(self, delta_table_builder_mock, mock_target_df):
        with mock.patch("bietlejuice.loaders.delta_loader.DeltaTable") as delta_table:
            delta_table.isDeltaTable.return_value = True
            delta_table.createIfNotExists.return_value = delta_table_builder_mock
            delta_table.createOrReplace.return_value = delta_table_builder_mock
            delta_table.forName.return_value = mock_target_df

            yield delta_table

    @pytest.fixture
    def mock_source_df(self):
        source_df = mock.MagicMock()
        source_df.schema = ["column1", "column2"]
        source_df.alias = source_df
        dataframe_writer = mock.MagicMock()
        dataframe_writer.format.return_value = dataframe_writer
        dataframe_writer.option.return_value = dataframe_writer
        dataframe_writer.mode.return_value = dataframe_writer
        source_df.write = dataframe_writer
        return source_df

    @pytest.fixture(autouse=True)
    def mock_spark_context(self):
        with mock.patch(
            "bietlejuice.loaders.delta_loader.BaseSparkContext"
        ) as mock_spark_context:
            mock_spark_context.spark.catalog.tableExists.return_value = True
            yield mock_spark_context

    def test_create_empty_table_when_it_doesnt_exist(
        self,
        mock_spark_context,
        mock_delta_table,
        delta_table_builder_mock,
        mock_source_df,
    ):
        table_name = "test_database.test_table"
        path = "test_path"
        partition_by = ["column1", "column2"]
        mock_spark_context.spark.catalog.tableExists.return_value = False

        delta_loader = DeltaLoader()
        delta_loader.load_table(table_name, path, mock_source_df, partition_by)

        mock_spark_context.spark.sql.assert_called_once_with(
            "CREATE DATABASE IF NOT EXISTS `test_database`"
        )
        mock_delta_table.createIfNotExists.assert_called_once_with(
            mock_spark_context.spark
        )
        delta_table_builder_mock.tableName.assert_called_once_with(table_name)
        delta_table_builder_mock.addColumns.assert_called_once_with(
            mock_source_df.schema
        )
        delta_table_builder_mock.location.assert_called_once_with(path)
        delta_table_builder_mock.partitionedBy.assert_called_once_with(*partition_by)
        delta_table_builder_mock.execute.assert_called_once()

    def test_convert_to_delta_when_it_exists_but_is_not_delta(
        self, mock_spark_context, mock_delta_table, mock_source_df
    ):
        table_name = "test_table"
        mock_spark_context.spark.catalog.tableExists.return_value = True
        mock_delta_table.isDeltaTable.return_value = False

        delta_loader = DeltaLoader()
        delta_loader.load_table(table_name, None, mock_source_df)

        mock_spark_context.spark.sql.assert_called_with("CONVERT TO DELTA test_table")

    def test_convert_to_delta_should_drop_table_if_it_exists_in_parquet_but_is_empty(
        self,
        mock_spark_context,
        mock_delta_table,
        mock_source_df,
        delta_table_builder_mock,
    ):
        table_name = "test_table"
        mock_spark_context.spark.catalog.tableExists.return_value = True
        mock_delta_table.isDeltaTable.return_value = False
        expected_error = Py4JJavaError("File not found", mock.MagicMock())
        expected_error.java_exception.getClass().getName.return_value = (
            "java.io.FileNotFoundException"
        )
        mock_spark_context.spark.sql.side_effect = [
            mock.MagicMock(),
            expected_error,
            mock.MagicMock(),
        ]

        delta_loader = DeltaLoader()
        delta_loader.load_table(table_name, None, mock_source_df)

        mock_spark_context.spark.sql.assert_any_call("CONVERT TO DELTA test_table")
        mock_spark_context.spark.sql.assert_any_call("DROP TABLE test_table")
        delta_table_builder_mock.execute.assert_called_once()

    @mock.patch("bietlejuice.loaders.delta_loader.AnalysisException.getErrorClass")
    def test_convert_to_delta_should_drop_table_if_it_exists_in_delta_but_is_empty(
        self,
        mock_analysis_exception_class,
        mock_spark_context,
        mock_delta_table,
        mock_source_df,
        delta_table_builder_mock,
    ):
        table_name = "test_table"
        mock_spark_context.spark.catalog.tableExists.return_value = True
        mock_delta_table.isDeltaTable.return_value = False
        mock_analysis_exception_class.return_value = "DELTA_TABLE_NOT_FOUND"
        mock_spark_context.spark.sql.side_effect = [
            mock.MagicMock(),
            AnalysisException(desc="DELTA_TABLE_NOT_FOUND", stackTrace=""),
            mock.MagicMock(),
        ]

        delta_loader = DeltaLoader()
        delta_loader.load_table(table_name, None, mock_source_df)

        mock_spark_context.spark.sql.assert_any_call("CONVERT TO DELTA test_table")
        mock_spark_context.spark.sql.assert_any_call("DROP TABLE test_table")
        delta_table_builder_mock.execute.assert_called_once()

    def test_write_to_table(self, mock_source_df):
        table_name = "test_table"
        path = "test_path"
        partition_by = ["column1", "column2"]
        merge_schema = True

        delta_loader = DeltaLoader()
        delta_loader.load_table(
            table_name, path, mock_source_df, partition_by, merge_schema
        )

        mock_source_df.write.format.assert_called_once_with("delta")
        mock_source_df.write.option.assert_called_once_with("mergeSchema", merge_schema)
        mock_source_df.write.mode.assert_called_once_with("overwrite")
        mock_source_df.write.saveAsTable.assert_called_once_with(
            table_name, path=path, partitionBy=partition_by
        )

    def test_merge_to_table_without_delete(
        self,
        mock_delta_table,
        merge_builder_mock,
        mock_source_df,
        mock_spark_context,
        mock_target_df,
    ):
        table_name = "test_table"
        merge_on = ["column1", "column2"]
        when_not_matched_insert_condition = "condition1"
        when_matched_update_condition = "condition2"

        delta_loader = DeltaLoader()
        delta_loader.load_table(
            table_name,
            None,
            mock_source_df,
            merge_on=merge_on,
            when_not_matched_insert_condition=when_not_matched_insert_condition,
            when_matched_update_condition=when_matched_update_condition,
        )

        mock_source_df.alias.assert_called_once_with("source")
        mock_target_df.alias.assert_called_once_with("target")
        mock_target_df.merge.assert_called_once_with(
            mock_source_df.alias("source"),
            "source.column1 = target.column1 AND source.column2 = target.column2",
        )
        mock_delta_table.forName.assert_called_once_with(
            mock_spark_context.spark, table_name
        )
        merge_builder_mock.whenNotMatchedInsertAll.assert_called_once_with(
            condition=when_not_matched_insert_condition
        )
        merge_builder_mock.whenMatchedUpdateAll.assert_called_once_with(
            condition=when_matched_update_condition
        )
        merge_builder_mock.whenMatchedDelete.assert_not_called()
        merge_builder_mock.execute.assert_called_once()

    def test_merge_to_table_with_delete(
        self,
        mock_delta_table,
        merge_builder_mock,
        mock_source_df,
        mock_spark_context,
        mock_target_df,
    ):
        table_name = "test_table"
        merge_on = ["column1", "column2"]
        when_not_matched_insert_condition = "condition1"
        when_matched_update_condition = "condition2"
        when_matched_delete_condition = "condition3"

        delta_loader = DeltaLoader()
        delta_loader.load_table(
            table_name,
            None,
            mock_source_df,
            merge_on=merge_on,
            when_not_matched_insert_condition=when_not_matched_insert_condition,
            when_matched_update_condition=when_matched_update_condition,
            when_matched_delete_condition=when_matched_delete_condition,
        )

        mock_source_df.alias.assert_called_once_with("source")
        mock_target_df.alias.assert_called_once_with("target")
        mock_target_df.merge.assert_called_once_with(
            mock_source_df.alias("source"),
            "source.column1 = target.column1 AND source.column2 = target.column2",
        )
        mock_delta_table.forName.assert_called_once_with(
            mock_spark_context.spark, table_name
        )
        merge_builder_mock.whenNotMatchedInsertAll.assert_called_once_with(
            condition=when_not_matched_insert_condition
        )
        merge_builder_mock.whenMatchedUpdateAll.assert_called_once_with(
            condition=when_matched_update_condition
        )
        merge_builder_mock.whenMatchedDelete.assert_called_once_with(
            condition=when_matched_delete_condition
        )
        merge_builder_mock.execute.assert_called_once()

    def test_vacuum_table(self, mock_spark_context):
        table_name = "test_table"
        retention_hours = 24

        delta_loader = DeltaLoader()
        delta_loader.vacuum_table(table_name, retention_hours)

        mock_spark_context.spark.sql.assert_called_once_with(
            f"VACUUM test_table RETAIN 24 HOURS"
        )

    def test_optimize_table_without_z_order(self, mock_spark_context):
        table_name = "test_table"

        delta_loader = DeltaLoader()
        delta_loader.optimize_table(table_name)

        mock_spark_context.spark.sql.assert_called_once_with(f"OPTIMIZE test_table")

    def test_optimize_table_with_z_order(self, mock_spark_context):
        table_name = "test_table"
        z_order_by = ["column1", "column2"]

        delta_loader = DeltaLoader()
        delta_loader.optimize_table(table_name, z_order_by)

        mock_spark_context.spark.sql.assert_called_once_with(
            f"OPTIMIZE test_table ZORDER BY column1,column2"
        )
