from unittest import mock

import pytest
from py4j.protocol import Py4JJavaError
from pyspark.sql.types import StringType, StructField, StructType
from pyspark.sql.utils import AnalysisException

from bietlejuice.loaders.delta_loader import DeltaLoader, _check_identifier_safety


class TestDeltaLoader:
    @pytest.fixture
    def delta_table_builder_mock(self):
        builder = mock.MagicMock()
        builder.tableName.return_value = builder
        builder.property.return_value = builder
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
        target_df.schema = StructType(
            [StructField("column1", StringType()), StructField("column2", StringType())]
        )
        target_df.alias.return_value = target_df
        target_df.merge.return_value = merge_builder_mock
        return target_df

    @pytest.fixture
    def mock_delta_table(self, delta_table_builder_mock, mock_target_df):
        with mock.patch("bietlejuice.loaders.delta_loader.DeltaTable") as delta_table:
            delta_table.isDeltaTable.return_value = False
            delta_table.createIfNotExists.return_value = delta_table_builder_mock
            delta_table.createOrReplace.return_value = delta_table_builder_mock
            delta_table.forName.return_value = mock_target_df

            yield delta_table

    @pytest.fixture
    def mock_source_df(self):
        source_df = mock.MagicMock()
        source_df.schema = StructType(
            [StructField("column1", StringType()), StructField("column2", StringType())]
        )
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
        mock_delta_table.forName.side_effect = AnalysisException(
            "DELTA_TABLE_NOT_FOUND"
        )
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)

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

    def test_registers_existing_delta_at_path_when_metastore_missing(
        self,
        mock_spark_context,
        mock_delta_table,
        delta_table_builder_mock,
        mock_source_df,
    ):
        table_name = "test_database.test_table"
        path = "s3://bucket/transactional/schema/table/"
        mock_spark_context.spark.catalog.tableExists.return_value = False
        mock_delta_table.forName.side_effect = AnalysisException(
            "DELTA_TABLE_NOT_FOUND"
        )
        mock_delta_table.isDeltaTable.return_value = True
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)

        delta_loader.load_table(table_name, path, mock_source_df)

        mock_delta_table.isDeltaTable.assert_called_once_with(
            mock_spark_context.spark, path
        )
        mock_spark_context.spark.sql.assert_any_call(
            "CREATE TABLE IF NOT EXISTS `test_database`.`test_table` USING DELTA "
            f"LOCATION '{path}'"
        )
        mock_delta_table.createIfNotExists.assert_not_called()
        delta_table_builder_mock.execute.assert_not_called()

    def test_create_empty_table_converts_not_nullable_to_nullable(
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
        mock_source_df.schema = StructType(
            [
                StructField("column1", StringType(), nullable=True),
                StructField("column2", StringType(), nullable=False),
            ]
        )

        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        delta_loader.load_table(table_name, path, mock_source_df, partition_by)

        delta_table_builder_mock.addColumns.assert_called_once_with(
            StructType(
                [
                    StructField("column1", StringType(), nullable=True),
                    StructField("column2", StringType(), nullable=True),
                ]
            )
        )

    def test_convert_to_delta_when_it_exists_but_is_not_delta(
        self, mock_spark_context, mock_delta_table, mock_source_df
    ):
        table_name = "test_table"
        mock_spark_context.spark.catalog.tableExists.return_value = True
        mock_delta_table.forName.side_effect = AnalysisException(
            "DELTA_TABLE_NOT_FOUND"
        )

        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
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
        mock_delta_table.forName.side_effect = AnalysisException(
            "DELTA_TABLE_NOT_FOUND"
        )
        expected_error = Py4JJavaError("File not found", mock.MagicMock())
        expected_error.java_exception.getClass().getName.return_value = (
            "java.io.FileNotFoundException"
        )
        mock_spark_context.spark.sql.side_effect = [
            mock.MagicMock(),
            expected_error,
            mock.MagicMock(),
        ]

        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
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
        mock_delta_table.forName.side_effect = AnalysisException(
            "DELTA_TABLE_NOT_FOUND"
        )
        mock_analysis_exception_class.return_value = "DELTA_TABLE_NOT_FOUND"
        mock_spark_context.spark.sql.side_effect = [
            mock.MagicMock(),
            AnalysisException("DELTA_TABLE_NOT_FOUND"),
            mock.MagicMock(),
        ]

        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        delta_loader.load_table(table_name, None, mock_source_df)

        mock_spark_context.spark.sql.assert_any_call("CONVERT TO DELTA test_table")
        mock_spark_context.spark.sql.assert_any_call("DROP TABLE test_table")
        delta_table_builder_mock.execute.assert_called_once()

    @mock.patch("bietlejuice.loaders.delta_loader.AnalysisException.getErrorClass")
    def test_convert_to_delta_should_drop_table_if_it_exists_in_parquet_and_partitioned_but_is_empty(
        self,
        mock_analysis_exception_class,
        mock_spark_context,
        mock_delta_table,
        mock_source_df,
        delta_table_builder_mock,
    ):
        table_name = "test_table"
        mock_spark_context.spark.catalog.tableExists.return_value = True
        mock_delta_table.forName.side_effect = AnalysisException(
            "DELTA_TABLE_NOT_FOUND"
        )
        mock_analysis_exception_class.return_value = (
            "DELTA_CONVERSION_NO_PARTITION_FOUND"
        )
        mock_spark_context.spark.sql.side_effect = [
            mock.MagicMock(),
            AnalysisException("DELTA_CONVERSION_NO_PARTITION_FOUND"),
            mock.MagicMock(),
        ]

        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        delta_loader.load_table(table_name, None, mock_source_df)

        mock_spark_context.spark.sql.assert_any_call("CONVERT TO DELTA test_table")
        mock_spark_context.spark.sql.assert_any_call("DROP TABLE test_table")
        delta_table_builder_mock.execute.assert_called_once()

    def test_create_empty_table_with_column_mapping_mode(
        self,
        mock_spark_context,
        mock_delta_table,
        delta_table_builder_mock,
        mock_source_df,
    ):
        table_name = "test_database.test_table"
        path = "test_path"
        mock_spark_context.spark.catalog.tableExists.return_value = False
        mock_delta_table.forName.side_effect = AnalysisException(
            "DELTA_TABLE_NOT_FOUND"
        )
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)

        delta_loader.load_table(
            table_name, path, mock_source_df, column_mapping_mode="name"
        )

        delta_table_builder_mock.property.assert_called_once_with(
            "delta.columnMapping.mode", "name"
        )

    def test_create_empty_table_without_column_mapping_mode(
        self,
        mock_spark_context,
        mock_delta_table,
        delta_table_builder_mock,
        mock_source_df,
    ):
        table_name = "test_database.test_table"
        path = "test_path"
        mock_spark_context.spark.catalog.tableExists.return_value = False
        mock_delta_table.forName.side_effect = AnalysisException(
            "DELTA_TABLE_NOT_FOUND"
        )
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)

        delta_loader.load_table(table_name, path, mock_source_df)

        delta_table_builder_mock.property.assert_not_called()

    def test_write_to_table(self, mock_spark_context, mock_source_df, mock_delta_table):
        table_name = "test_table"
        path = "test_path"
        partition_by = ["column1", "column2"]
        merge_schema = True
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        delta_loader.load_table(
            table_name, path, mock_source_df, partition_by, merge_schema
        )

        mock_source_df.write.format.assert_called_once_with("delta")
        mock_source_df.write.option.assert_any_call("mergeSchema", True)
        mock_source_df.write.option.assert_any_call("overwriteSchema", False)
        mock_source_df.write.mode.assert_called_once_with("overwrite")
        mock_source_df.write.saveAsTable.assert_called_once_with(
            table_name, partitionBy=partition_by
        )

    def test_write_to_table_with_column_mapping_mode(
        self, mock_spark_context, mock_source_df, mock_delta_table
    ):
        table_name = "test_table"
        path = "test_path"
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        delta_loader.load_table(
            table_name, path, mock_source_df, column_mapping_mode="name"
        )

        mock_spark_context.spark.sql.assert_any_call(
            "ALTER TABLE test_table SET TBLPROPERTIES "
            "('delta.columnMapping.mode' = 'name')"
        )

    def test_write_to_table_without_column_mapping_mode(
        self, mock_spark_context, mock_source_df, mock_delta_table
    ):
        table_name = "test_table"
        path = "test_path"
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        delta_loader.load_table(table_name, path, mock_source_df)

        for call in mock_spark_context.spark.sql.call_args_list:
            assert "delta.columnMapping.mode" not in str(call)

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

        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
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
        mock_delta_table.forName.assert_has_calls(
            [
                mock.call(mock_spark_context.spark, table_name),
                mock.call(mock_spark_context.spark, table_name),
            ]
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

        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
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
        mock_delta_table.forName.assert_has_calls(
            [
                mock.call(mock_spark_context.spark, table_name),
                mock.call(mock_spark_context.spark, table_name),
            ]
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

    def test_merge_to_table_rejects_malicious_merge_on_column(
        self, mock_delta_table, mock_source_df, mock_spark_context
    ):
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        with pytest.raises(ValueError, match="Invalid SQL identifier"):
            delta_loader.load_table(
                "test_table",
                None,
                mock_source_df,
                merge_on=["column1", "'; DROP TABLE users --"],
            )

    def test_vacuum_table(self, mock_spark_context):
        table_name = "test_table"
        retention_hours = 24

        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        delta_loader.vacuum_table(table_name, retention_hours)

        mock_spark_context.spark.sql.assert_has_calls(
            [
                mock.call(
                    "ALTER TABLE test_table SET TBLPROPERTIES ('delta.deletedFileRetentionDuration'='24 hours')"
                ),
                mock.call("VACUUM `test_table`"),
            ]
        )

    def test_vacuum_lite_table(self, mock_spark_context):
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        delta_loader.vacuum_lite_table("test_table", 24)

        mock_spark_context.spark.sql.assert_has_calls(
            [
                mock.call(
                    "ALTER TABLE test_table SET TBLPROPERTIES ('delta.deletedFileRetentionDuration'='24 hours')"
                ),
                mock.call("VACUUM `test_table` LITE"),
            ]
        )

    @pytest.mark.parametrize(
        "lite_error",
        [
            # Delta 3.3+ refusing LITE because the log cannot back it.
            RuntimeError(
                "org.apache.spark.sql.delta.DeltaIllegalStateException: "
                "[DELTA_CANNOT_VACUUM_LITE] VACUUM LITE cannot delete all eligible files"
            ),
            # DBR < 16.1 / Delta < 3.3: LITE is not valid syntax.
            RuntimeError(
                "[PARSE_SYNTAX_ERROR] Syntax error at or near 'VACUUM'.(line 1, pos 0)\n\n"
                "== SQL ==\nVACUUM `test_table` LITE\n^^^"
            ),
        ],
        ids=["cannot_vacuum_lite", "lite_syntax_unsupported"],
    )
    def test_vacuum_lite_table_falls_back_to_full_vacuum(
        self, mock_spark_context, lite_error
    ):
        def sql_side_effect(command):
            if command.endswith("LITE"):
                raise lite_error
            return mock.MagicMock()

        mock_spark_context.spark.sql.side_effect = sql_side_effect

        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        delta_loader.vacuum_lite_table("test_table", 24)

        mock_spark_context.spark.sql.assert_has_calls(
            [
                mock.call("VACUUM `test_table` LITE"),
                mock.call("VACUUM `test_table`"),
            ]
        )

    # ---- VACUUM LITE watermark bootstrap ----

    # Captured verbatim from a real successful `VACUUM ... LITE` on delta-spark 3.3.1.
    # If Delta changes the shape, re-capture it; do not hand-adjust.
    EXPECTED_WATERMARK_PAYLOAD = b'{"latestCommitVersionOutsideOfRetentionWindow":10}\n'

    @staticmethod
    def _lite_fails(command):
        if command.endswith("LITE"):
            raise RuntimeError(
                "org.apache.spark.sql.delta.DeltaIllegalStateException: "
                "[DELTA_CANNOT_VACUUM_LITE] forced"
            )
        return mock.MagicMock()

    @staticmethod
    def _commit_status(name):
        status = mock.MagicMock()
        status.getPath.return_value.getName.return_value = name
        return status

    def test_vacuum_lite_fallback_persists_watermark_when_enabled(
        self, mock_spark_context
    ):
        mock_spark_context.spark.sql.side_effect = self._lite_fails
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)

        with mock.patch.object(
            DeltaLoader, "_persist_vacuum_lite_watermark"
        ) as persist:
            delta_loader.vacuum_lite_table("test_table", 24, bootstrap_watermark=True)

        mock_spark_context.spark.sql.assert_has_calls(
            [
                mock.call("VACUUM `test_table` LITE"),
                mock.call("VACUUM `test_table`"),
            ]
        )
        persist.assert_called_once_with("test_table")

    def test_vacuum_lite_fallback_skips_watermark_by_default(self, mock_spark_context):
        mock_spark_context.spark.sql.side_effect = self._lite_fails
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)

        with mock.patch.object(
            DeltaLoader, "_persist_vacuum_lite_watermark"
        ) as persist:
            delta_loader.vacuum_lite_table("test_table", 24)

        mock_spark_context.spark.sql.assert_has_calls(
            [mock.call("VACUUM `test_table`")]
        )
        persist.assert_not_called()

    def test_watermark_not_written_when_full_vacuum_fails(self, mock_spark_context):
        def sql_side_effect(command):
            if command.startswith("VACUUM"):
                raise RuntimeError("table not found")
            return mock.MagicMock()

        mock_spark_context.spark.sql.side_effect = sql_side_effect
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)

        with mock.patch.object(
            DeltaLoader, "_persist_vacuum_lite_watermark"
        ) as persist:
            with pytest.raises(RuntimeError, match="table not found"):
                delta_loader.vacuum_lite_table(
                    "test_table", 24, bootstrap_watermark=True
                )

        persist.assert_not_called()

    def test_vacuum_table_does_not_persist_watermark(self, mock_spark_context):
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)

        with mock.patch.object(
            DeltaLoader, "_persist_vacuum_lite_watermark"
        ) as persist:
            delta_loader.vacuum_table("test_table", 24)

        persist.assert_not_called()

    def test_watermark_failure_does_not_fail_vacuum(self, mock_spark_context):
        """The guardrail that matters: the vacuum itself already succeeded."""
        mock_spark_context.spark.sql.side_effect = self._lite_fails
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)

        with mock.patch.object(
            DeltaLoader, "_delta_log_dir", side_effect=RuntimeError("no location")
        ):
            delta_loader.vacuum_lite_table("test_table", 24, bootstrap_watermark=True)

        mock_spark_context.spark.sql.assert_has_calls(
            [mock.call("VACUUM `test_table`")]
        )

    def test_watermark_payload_matches_delta_format(self, mock_spark_context):
        spark = mock_spark_context.spark
        stream = mock.MagicMock()
        fs = mock.MagicMock()
        fs.create.return_value = stream
        fs.listStatus.return_value = [
            self._commit_status("00000000000000000012.json"),
            self._commit_status("00000000000000000010.json"),
            self._commit_status("00000000000000000010.checkpoint.parquet"),
            self._commit_status("_last_vacuum_info"),
        ]
        spark._jvm.org.apache.hadoop.fs.Path.return_value.getFileSystem.return_value = (
            fs
        )

        delta_loader = DeltaLoader(spark=spark)
        with mock.patch.object(
            DeltaLoader, "_delta_log_dir", return_value="s3://bucket/t/_delta_log"
        ):
            delta_loader._persist_vacuum_lite_watermark("test_table")

        # earliest retained commit is 10 - not the checkpoint, not 12
        assert bytes(stream.write.call_args[0][0]) == self.EXPECTED_WATERMARK_PAYLOAD
        stream.close.assert_called_once()
        # overwrite=True, so the null watermark left by the full vacuum is replaced
        assert fs.create.call_args[0][1] is True

    def test_watermark_skipped_when_no_commit_files(self, mock_spark_context):
        spark = mock_spark_context.spark
        fs = mock.MagicMock()
        fs.listStatus.return_value = [self._commit_status("_last_vacuum_info")]
        spark._jvm.org.apache.hadoop.fs.Path.return_value.getFileSystem.return_value = (
            fs
        )

        delta_loader = DeltaLoader(spark=spark)
        with mock.patch.object(
            DeltaLoader, "_delta_log_dir", return_value="s3://bucket/t/_delta_log"
        ):
            delta_loader._persist_vacuum_lite_watermark("test_table")

        fs.create.assert_not_called()

    def test_vacuum_lite_table_propagates_full_vacuum_failure(self, mock_spark_context):
        def sql_side_effect(command):
            if command.startswith("VACUUM"):
                raise RuntimeError("table not found")
            return mock.MagicMock()

        mock_spark_context.spark.sql.side_effect = sql_side_effect

        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        with pytest.raises(RuntimeError, match="table not found"):
            delta_loader.vacuum_lite_table("test_table", 24)

    def test_optimize_table_without_z_order(self, mock_spark_context):
        table_name = "test_table"

        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        delta_loader.optimize_table(table_name)

        mock_spark_context.spark.sql.assert_called_once_with("OPTIMIZE `test_table`")

    def test_optimize_table_with_z_order(self, mock_spark_context):
        table_name = "test_table"
        z_order_by = ["column1", "column2"]

        delta_loader = DeltaLoader(spark=mock_spark_context.spark)

        delta_loader.optimize_table(table_name, z_order_by)

        mock_spark_context.spark.sql.assert_called_once_with(
            "OPTIMIZE `test_table` ZORDER BY column1,column2"
        )

    def test_optimize_table_rejects_malicious_z_order_column(self, mock_spark_context):
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        with pytest.raises(ValueError, match="Invalid SQL identifier"):
            delta_loader.optimize_table("test_table", ["column1", "'; evil --"])

    def test_optimize_table_with_where_predicate(self, mock_spark_context):
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        delta_loader.optimize_table(
            "test_table",
            where_predicate="year = 2026 AND month = 5 AND day = 26",
        )
        mock_spark_context.spark.sql.assert_called_once_with(
            "OPTIMIZE `test_table` WHERE year = 2026 AND month = 5 AND day = 26"
        )

    def test_optimize_table_quotes_reserved_word_table_name(self, mock_spark_context):
        # arrange
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        table_name = "datalake_bob_transactional.location"
        where_predicate = (
            "(year = 2026 AND month = 5 AND day = 26) OR "
            "(year = 2026 AND month = 5 AND day = 27)"
        )

        # act
        delta_loader.optimize_table(table_name, where_predicate=where_predicate)

        # assert
        mock_spark_context.spark.sql.assert_called_once_with(
            "OPTIMIZE `datalake_bob_transactional`.`location` WHERE "
            "(year = 2026 AND month = 5 AND day = 26) OR "
            "(year = 2026 AND month = 5 AND day = 27)"
        )

    def test_optimize_table_with_where_predicate_and_z_order(self, mock_spark_context):
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        delta_loader.optimize_table(
            "test_table",
            z_order_by=["column1", "column2"],
            where_predicate="year = 2026 AND month = 5 AND day = 26",
        )
        mock_spark_context.spark.sql.assert_called_once_with(
            "OPTIMIZE `test_table` WHERE year = 2026 AND month = 5 AND day = 26 "
            "ZORDER BY column1,column2"
        )

    @pytest.mark.parametrize(
        "identifier",
        ["test_table", "db.table", "datalake_ebdb_raw.contract"],
    )
    def test_check_identifier_safety_accepts_valid_names(self, identifier):
        _check_identifier_safety(identifier)  # must not raise

    @pytest.mark.parametrize(
        "identifier",
        ["'; DROP TABLE --", "table; SELECT 1", "name WITH spaces", ""],
    )
    def test_check_identifier_safety_rejects_malicious_input(self, identifier):
        with pytest.raises(ValueError, match="Invalid SQL identifier"):
            _check_identifier_safety(identifier)

    def test_write_to_table_rejects_invalid_column_mapping_mode(
        self, mock_spark_context, mock_source_df, mock_delta_table
    ):
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        with pytest.raises(ValueError, match="Invalid column_mapping_mode"):
            delta_loader.load_table(
                "test_table",
                "test_path",
                mock_source_df,
                column_mapping_mode="'; DROP TABLE evil --",
            )

    @pytest.mark.parametrize(
        "malicious_name",
        ["'; DROP TABLE users --", "table; SELECT 1", "evil name", ""],
    )
    def test_load_table_rejects_malicious_table_name(
        self, mock_spark_context, mock_source_df, mock_delta_table, malicious_name
    ):
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        with pytest.raises(ValueError, match="Invalid SQL identifier"):
            delta_loader.load_table(malicious_name, "some_path", mock_source_df)

    @pytest.mark.parametrize(
        "malicious_name",
        ["'; VACUUM users --", "table; DROP TABLE evil", "bad name"],
    )
    def test_vacuum_table_rejects_malicious_table_name(
        self, mock_spark_context, malicious_name
    ):
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        with pytest.raises(ValueError, match="Invalid SQL identifier"):
            delta_loader.vacuum_table(malicious_name, 24)

    @pytest.mark.parametrize(
        "malicious_name",
        ["'; VACUUM users --", "table; DROP TABLE evil", "bad name"],
    )
    def test_vacuum_lite_table_rejects_malicious_table_name(
        self, mock_spark_context, malicious_name
    ):
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        with pytest.raises(ValueError, match="Invalid SQL identifier"):
            delta_loader.vacuum_lite_table(malicious_name, 24)

    @pytest.mark.parametrize(
        "malicious_name",
        ["'; OPTIMIZE evil --", "table; DROP TABLE foo", "bad name"],
    )
    def test_optimize_table_rejects_malicious_table_name(
        self, mock_spark_context, malicious_name
    ):
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)
        with pytest.raises(ValueError, match="Invalid SQL identifier"):
            delta_loader.optimize_table(malicious_name)

    # -- target-type alignment -------------------------------------------------

    @pytest.fixture
    def mock_align(self):
        """Patch the alignment hook, defaulting to a pass-through."""
        with mock.patch(
            "bietlejuice.loaders.delta_loader.align_source_to_target",
            side_effect=lambda _spark, source_df, _table: source_df,
        ) as align:
            yield align

    @pytest.fixture
    def aligned_df(self):
        """A distinct DataFrame, so we can prove the write used the cast one."""
        df = mock.MagicMock()
        df.alias.return_value = df
        writer = mock.MagicMock()
        writer.format.return_value = writer
        writer.option.return_value = writer
        writer.mode.return_value = writer
        df.write = writer
        return df

    def test_aligns_source_to_target_when_table_already_exists(
        self, mock_spark_context, mock_delta_table, mock_source_df, mock_align
    ):
        """Raw JSON registers timestamp/date as string; the target keeps the
        real type, so the source is cast to what the table already declares."""
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)

        delta_loader.load_table("test_database.test_table", "test_path", mock_source_df)

        mock_align.assert_called_once_with(
            mock_spark_context.spark, mock_source_df, "test_database.test_table"
        )

    def test_does_not_align_a_table_created_from_the_source(
        self, mock_spark_context, mock_delta_table, mock_source_df, mock_align
    ):
        """A freshly created table has the source's own types — nothing to align."""
        mock_spark_context.spark.catalog.tableExists.return_value = False
        mock_delta_table.forName.side_effect = AnalysisException(
            "DELTA_TABLE_NOT_FOUND"
        )
        mock_delta_table.isDeltaTable.return_value = False
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)

        delta_loader.load_table("test_database.test_table", "test_path", mock_source_df)

        mock_align.assert_not_called()

    def test_aligns_after_registering_existing_delta_at_path(
        self, mock_spark_context, mock_delta_table, mock_source_df, mock_align
    ):
        """Delta data already at the path keeps its own schema, so align to it."""
        path = "s3://bucket/transactional/schema/table/"
        mock_spark_context.spark.catalog.tableExists.return_value = False
        mock_delta_table.forName.side_effect = AnalysisException(
            "DELTA_TABLE_NOT_FOUND"
        )
        mock_delta_table.isDeltaTable.return_value = True
        delta_loader = DeltaLoader(spark=mock_spark_context.spark)

        delta_loader.load_table("test_database.test_table", path, mock_source_df)

        mock_align.assert_called_once_with(
            mock_spark_context.spark, mock_source_df, "test_database.test_table"
        )

    def test_merge_uses_the_aligned_dataframe(
        self,
        mock_spark_context,
        mock_delta_table,
        mock_target_df,
        mock_source_df,
        aligned_df,
    ):
        with mock.patch(
            "bietlejuice.loaders.delta_loader.align_source_to_target",
            return_value=aligned_df,
        ):
            delta_loader = DeltaLoader(spark=mock_spark_context.spark)
            delta_loader.load_table(
                "test_table", None, mock_source_df, merge_on=["column1"]
            )

        mock_target_df.merge.assert_called_once_with(
            aligned_df, "source.column1 = target.column1"
        )
        mock_source_df.alias.assert_not_called()

    def test_write_uses_the_aligned_dataframe(
        self,
        mock_spark_context,
        mock_delta_table,
        mock_source_df,
        aligned_df,
    ):
        with mock.patch(
            "bietlejuice.loaders.delta_loader.align_source_to_target",
            return_value=aligned_df,
        ):
            delta_loader = DeltaLoader(spark=mock_spark_context.spark)
            delta_loader.load_table("test_table", "test_path", mock_source_df)

        aligned_df.write.format.assert_called_once_with("delta")
        aligned_df.write.saveAsTable.assert_called_once_with(
            "test_table", partitionBy=None
        )
        mock_source_df.write.format.assert_not_called()
