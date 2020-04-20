import pytest


class TestSparkMetastoreLoader:
    @pytest.mark.parametrize(
        "format_options, mode, database_name, table_name, database_location",
        [
            ("parquet", "append", "", "test", "local/path"),
            ("csv", "overwrite", "house", "real", "s3://path"),
        ],
    )
    def test_save_as_table(
        self, format_options, mode, database_name, table_name, database_location, mocked_write_df, metastore_loader
    ):
        # given
        s3_path = database_location + table_name
        name = "{}.{}".format(database_name, table_name)
        partitions = []

        # when
        metastore_loader.update_metastore(
            df=mocked_write_df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location
        )

        # then
        mocked_write_df.write.mode("ignore").format(format_options).option("path", s3_path).saveAsTable.assert_called_with(name)

    @pytest.mark.parametrize(
        "database_name, table_name, format_options, database_location", [(None, "table", None, None), ("database", None, None, None), ("database", 123, None, None)],
    )
    def test_save_as_table_invalid_params(self, database_name, table_name, format_options, database_location, mocked_write_df, metastore_loader):
        # act and assert
        with pytest.raises(ValueError):
            metastore_loader.update_metastore(mocked_write_df, database_name, table_name, format_options, database_location)

    def test_save_as_table_with_invalid_df(self, metastore_loader):
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
                database_location=database_location
            )
