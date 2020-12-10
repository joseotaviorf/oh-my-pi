import pytest
from bietlejuice.jobs.composer.base.spark import BaseSparkContext


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
                **options
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
                **options
            )
