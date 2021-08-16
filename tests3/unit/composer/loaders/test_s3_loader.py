import pytest

from unittest import mock
from bietlejuice.jobs.composer.base.spark import BaseSparkContext
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader


class TestS3Loader:
    @pytest.mark.parametrize(
        "format_options, database_location, partitions, options",
        [("csv", "path/to/file", [], {"maxRecordsPerFile": 5})],
    )
    def test_load_full_table(
        self,
        format_options,
        database_location,
        partitions,
        options,
        mocked_write_df,
        s3_loader,
    ):
        # arrange
        database_name = "default"
        table_name = "test_table"
        path = database_location + table_name

        # act
        s3_loader.load_full_table(
            mocked_write_df,
            database_name,
            table_name,
            format_options,
            database_location,
            partitions,
        )

        # then
        mocked_write_df.write.mode("overwrite").format(format).option(
            **options
        ).save.assert_called_with(path=path)

    @pytest.mark.parametrize(
        "database_name, table_name, format_options, database_location, partitions, options",
        [("ebdb", "house", "csv", "path/to/file", [], {"maxRecordsPerFile": 5})],
    )
    def test_load_full_table_with_invalid_df(
        self,
        database_name,
        table_name,
        format_options,
        database_location,
        partitions,
        options,
        s3_loader,
    ):
        # arrange
        df = None

        with pytest.raises(ValueError):
            s3_loader.load_full_table(
                df,
                database_name,
                table_name,
                format_options,
                database_location,
                partitions,
                **options,
            )

    @pytest.mark.parametrize(
        "format_options, database_location, partitions, options",
        [("csv", "path/to/file", [], {"maxRecordsPerFile": 5})],
    )
    def test_load_incremental_table(
        self,
        format_options,
        database_location,
        partitions,
        options,
        mocked_write_df,
        s3_loader,
    ):
        # arrange
        spark = BaseSparkContext.spark
        spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")
        database_name = "default"
        table_name = "test_table"
        path = database_location + table_name

        # act
        s3_loader.load_incremental_table(
            mocked_write_df,
            database_name,
            table_name,
            format_options,
            database_location,
            partitions,
        )

        # then
        mocked_write_df.write.mode("overwrite").format(format).option(
            **options
        ).partitionBy(*partitions).save.assert_called_with(path=path)

    @pytest.mark.parametrize(
        "database_name, table_name, format_options, database_location, partitions, options",
        [("ebdb", "house", "csv", "path/to/file", [], {"maxRecordsPerFile": 5})],
    )
    def test_load_incremental_table_with_invalid_df(
        self,
        database_name,
        table_name,
        format_options,
        database_location,
        partitions,
        options,
        s3_loader,
    ):
        # arrange
        df = None

        with pytest.raises(ValueError):
            s3_loader.load_incremental_table(
                df,
                database_name,
                table_name,
                format_options,
                database_location,
                partitions,
                **options,
            )

    @mock.patch.object(S3Loader, "_optimize_dataframe_partitions")
    @pytest.mark.parametrize(
        "s3_path, format_options, partitions, write_mode, max_records_per_file, options, optimize_dataframe",
        [("path/to/file", "csv", [], "overwrite", 10, {"delimiter": ";"}, False)],
    )
    def test_load_df_full_with_success(
        self,
        mocked_optimization,
        s3_path,
        format_options,
        partitions,
        write_mode,
        max_records_per_file,
        options,
        optimize_dataframe,
        mocked_write_df,
        s3_loader,
    ):

        # arrange
        mocked_optimization.return_value = mocked_write_df
        df_writer = (
            mocked_write_df.write.mode(write_mode)
            .format(format_options)
            .option("maxRecordsPerFile", max_records_per_file)
            .option(**options)
        )

        # act
        s3_loader.load_df(
            mocked_write_df,
            s3_path,
            format_options,
            partitions,
            write_mode,
            max_records_per_file,
            optimize_dataframe,
            **options,
        )

        # then
        df_writer.save.assert_called_with(path=s3_path)

    @mock.patch.object(S3Loader, "_optimize_dataframe_partitions")
    @pytest.mark.parametrize(
        "s3_path, format_options, partitions, write_mode, max_records_per_file, options, optimize_dataframe",
        [
            (
                "path/to/file",
                "csv",
                ["particao_a", "particao_b"],
                "overwrite",
                10,
                {"delimiter": ";"},
                False,
            )
        ],
    )
    def test_load_df_incremental_with_success(
        self,
        mocked_optimization,
        s3_path,
        format_options,
        partitions,
        write_mode,
        max_records_per_file,
        options,
        optimize_dataframe,
        mocked_write_df,
        s3_loader,
    ):

        # arrange
        spark = BaseSparkContext.spark
        spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")
        mocked_optimization.return_value = mocked_write_df
        df_writer = (
            mocked_write_df.write.mode(write_mode)
            .format(format_options)
            .option("maxRecordsPerFile", max_records_per_file)
            .partitionBy(*partitions)
            .option(**options)
        )

        # act
        s3_loader.load_df(
            mocked_write_df,
            s3_path,
            format_options,
            partitions,
            write_mode,
            max_records_per_file,
            optimize_dataframe,
            **options,
        )

        # then
        df_writer.save.assert_called_with(path=s3_path)
