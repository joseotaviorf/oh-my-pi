import pytest


class TestSparkMetastoreLoader:
    @pytest.mark.parametrize(
        "format, mode, option",
        [
            ("csv", "overwrite", ("maxRecordsPerFile", 5))
        ],
    )
    def test_save_as_table(
        self, format, mode, option, mocked_spark_df_writer, mocked_metastore_loader
    ):
        # arrange
        database_name = "default"
        table_name = "test_table"
        name = '{}.{}'.format(database_name, table_name)

        # when
        mocked_df_writer = mocked_spark_df_writer.write.mode(mode).format(format).option(option[0], option[1])
        mocked_metastore_loader.save_as_table(
            df=mocked_df_writer,
            database_name=database_name,
            table_name=table_name
        )

        # then
        mocked_df_writer.saveAsTable.assert_called_with(name)

    @pytest.mark.parametrize(
        "database_name, table_name", [(None, "table"), ("database", None), ("database", 123)],
    )
    def test_save_as_table_invalid_params(self, database_name, table_name, mocked_df, mocked_metastore_loader):
        # act and assert
        with pytest.raises(ValueError):
            mocked_metastore_loader.save_as_table(mocked_df, database_name, table_name)

    def test_save_as_table_with_invalid_df(self, mocked_metastore_loader):
        # arrange
        database_name = "default"
        table_name = "test_table"
        df = None

        with pytest.raises(ValueError):
            mocked_metastore_loader.save_as_table(
                df=df,
                database_name=database_name,
                table_name=table_name,
            )
