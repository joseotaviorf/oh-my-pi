import pytest
from pyspark.sql import DataFrameWriter


class TestS3Loader:
    @pytest.mark.parametrize(
        "format, database_location, partitions, options",
        [
            ("csv", "path/to/file", [], {"maxRecordsPerFile": 5})
        ],
    )
    def test_load_full_table(
        self, format, database_location, partitions, options, mocked_df, mocked_s3_loader
    ):
        # arrange
        database_name = "default"
        table_name = "test_table"
        path = database_location + table_name
        name = '{}.{}'.format(database_name, table_name)

        # act
        result_df_writer = mocked_s3_loader.load_full_table(mocked_df, database_name, table_name, format, database_location, partitions, **options)

        # then
        assert type(result_df_writer) is DataFrameWriter

    @pytest.mark.parametrize(
        "database_name, table_name, format, database_location, partitions, options",
        [
            ("ebdb", "house", "csv", "path/to/file", [], {"maxRecordsPerFile": 5})
        ],
    )
    def test_load_full_table_with_invalid_df(self, database_name, table_name, format, database_location, partitions, options, mocked_s3_loader):
        # arrange
        df = None

        with pytest.raises(ValueError):
            mocked_s3_loader.load_full_table(df, database_name, table_name, format, database_location, partitions, **options)
