from collections import OrderedDict

import pytest
from mock import patch

from bietlejuice.services.schema_service import SchemaService


class TestSparkMetastoreLoader:
    @pytest.mark.parametrize(
        "format_options, mode, database_name, table_name, database_location",
        [
            ("parquet", "append", "", "test", "local/path"),
            ("csv", "overwrite", "house", "real", "s3://path"),
        ],
    )
    @patch.object(SchemaService, "get_schema_from_dataframe")
    def test_update_metastore(
        self,
        mocked_schema_service,
        format_options,
        mode,
        database_name,
        table_name,
        database_location,
        mocked_write_df,
        metastore_loader,
    ):
        # given
        s3_path = database_location + table_name
        partitions = []
        df_schema = OrderedDict({"col": "string"})

        mocked_schema_service.return_value = df_schema
        metastore_loader.schema_service.get_schema_from_dataframe = (
            mocked_schema_service
        )

        # when
        metastore_loader.update_metastore(
            df=mocked_write_df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
        )

        # then
        metastore_loader.metastore_service.create_external_table.assert_called_with(
            database_name, table_name, s3_path, df_schema, partitions, format_options
        )

    @pytest.mark.parametrize(
        "database_name, table_name, format_options, database_location",
        [
            (None, "table", None, None),
            ("database", None, None, None),
            ("database", 123, None, None),
        ],
    )
    def test_update_metastore_with_invalid_params(
        self,
        database_name,
        table_name,
        format_options,
        database_location,
        mocked_write_df,
        metastore_loader,
    ):
        # act and assert
        with pytest.raises(ValueError):
            metastore_loader.update_metastore(
                mocked_write_df,
                database_name,
                table_name,
                format_options,
                database_location,
            )

    def test_update_metastore_with_invalid_df(self, metastore_loader):
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
                database_location=database_location,
            )
