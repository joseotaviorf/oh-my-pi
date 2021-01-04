from collections import OrderedDict
from unittest import mock

import pytest
from thrift_files.libraries.thrift_hive_metastore_client.ttypes import FieldSchema

from bietlejuice.jobs.composer.loaders import HiveMetastoreLoader


class TestHiveMetastoreLoader:
    @mock.patch.object(HiveMetastoreLoader, "_get_tables_difference")
    def test_compare_table_schema(
        self, mocked__get_tables_difference, hive_metastore_loader
    ):
        # arrange
        database_name = "datalake_ebdb_clean_prod"
        table_name = "house"
        source_columns = OrderedDict([("some_col_name", "type")])

        hive_table_columns = {"name": "type"}
        hive_metastore_loader.hive_metastore_service.get_table_columns.return_value = (
            hive_table_columns
        )

        added_cols = "<added cols>"
        removed_cols = "<removed cols>"
        mocked__get_tables_difference.return_value = added_cols, removed_cols

        # act
        returned_value = hive_metastore_loader.compare_table_schema(
            database_name, table_name, source_columns
        )

        # assert
        assert returned_value == {"added": added_cols, "removed": removed_cols}
        hive_metastore_loader.hive_metastore_service.get_table_columns.assert_called_once_with(
            database_name, table_name
        )
        mocked__get_tables_difference.assert_called_once_with(
            source_columns, hive_table_columns
        )

    @pytest.mark.parametrize(
        "table_source, metastore_columns, expected_value",
        [
            (
                OrderedDict([("id", "int"), ("name", "string")]),
                {"id": "int", "name": "string"},
                ([], []),
            ),
            (
                OrderedDict([("id", "int"), ("name", "string")]),
                {"id": "int"},
                ([FieldSchema(name="name", type="string", comment=None)], []),
            ),
            (
                OrderedDict([("id", "int")]),
                {"id": "int", "name": "string"},
                ([], ["name"]),
            ),
            (
                OrderedDict([("id", "int"), ("name", "string"), ("age", "int")]),
                {"id": "int", "name": "string", "age": "string"},
                (
                    [FieldSchema(name="age", type="int", comment=None)],
                    ["age"],
                ),  # col type changed: the col will be removed from hive and added again with the new type
            ),
        ],
    )
    def test__get_tables_difference(
        self, table_source, metastore_columns, expected_value, hive_metastore_loader
    ):
        # act
        returned_value = hive_metastore_loader._get_tables_difference(
            table_source, metastore_columns
        )

        # assert
        assert returned_value == expected_value
