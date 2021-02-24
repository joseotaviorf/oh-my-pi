from collections import OrderedDict
from unittest import mock
from unittest.mock import Mock

import pytest
from hive_metastore_client.builders import ColumnBuilder
from hive_metastore_client.builders import PartitionBuilder
from pytest import raises

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
        assert returned_value == (added_cols, removed_cols)
        hive_metastore_loader.hive_metastore_service.get_table_columns.assert_called_once_with(
            database_name, table_name, ignore_partition_keys=True
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
                ([ColumnBuilder(name="name", type="string", comment=None).build()], []),
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
                    [ColumnBuilder(name="age", type="int", comment=None).build()],
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

    def test_is_table_in_metastore(self, hive_metastore_loader):
        # arrange
        database_name = "datalake_ebdb_clean_prod"
        table_name = "house"

        mocked_hive_table_names = ["house", "house_aud"]
        hive_metastore_loader.hive_metastore_service.get_table_names.return_value = (
            mocked_hive_table_names
        )

        expected_value = True

        # act
        returned_value = hive_metastore_loader.is_table_in_metastore(
            database_name, table_name
        )

        # assert
        assert returned_value == expected_value
        hive_metastore_loader.hive_metastore_service.get_table_names.assert_called_once_with(
            database_name
        )

    def test_create_table(self, hive_metastore_loader):
        # arrange
        database_name = "datalake_ebdb_clean_prod"
        table_name = "user"
        table_schema = OrderedDict([("some_col_name", "type")])
        table_location = "<table_location>"
        partition_keys = "<partition_keys>"
        format_info = "<format_options>"

        # act
        hive_metastore_loader.create_table(
            database_name,
            table_name,
            table_location,
            table_schema,
            partition_keys,
            format_info,
        )

        # assert
        hive_metastore_loader.hive_metastore_service.create_external_table.assert_called_once_with(
            database_name,
            table_name,
            table_location,
            table_schema,
            partition_keys,
            format_info,
        )

    @mock.patch.object(HiveMetastoreLoader, "create_table")
    @mock.patch.object(HiveMetastoreLoader, "_check_partition_keys")
    @mock.patch.object(HiveMetastoreLoader, "is_table_in_metastore")
    @mock.patch.object(HiveMetastoreLoader, "compare_table_schema")
    def test_update_metastore_with_existing_table(
        self,
        mocked_compare_table_schema,
        mocked_is_table_in_metastore,
        mocked__check_partition_keys,
        mocked_create_table,
        hive_metastore_loader,
    ):
        # arrange
        table_schema = "<table_schema>"
        database_name = "<db_name>"
        table_name = "<tb_name>"
        format_info = "<format_info>"
        database_location = "<location>"
        source_schema = "<source schema>"
        partition_keys = "<partition_keys>"

        mocked_is_table_in_metastore.return_value = True

        mocked_added_cols = [ColumnBuilder("col3", "string").build()]
        mocked_removed_cols = ["col1", "col2"]
        mocked_compare_table_schema.return_value = (
            mocked_added_cols,
            mocked_removed_cols,
        )

        # act
        hive_metastore_loader.update_metastore(
            database_name,
            table_name,
            database_location,
            table_schema,
            partition_keys,
            format_info,
            source_schema,
        )

        # assert
        mocked_create_table.assert_not_called()
        mocked_is_table_in_metastore.assert_called_once_with(database_name, table_name)
        mocked_compare_table_schema.assert_called_once_with(
            database_name, table_name, source_schema
        )
        hive_metastore_loader.hive_metastore_service.drop_columns_from_table.assert_called_once_with(
            database_name, table_name, mocked_removed_cols
        )
        hive_metastore_loader.hive_metastore_service.add_columns_to_table.assert_called_once_with(
            database_name, table_name, mocked_added_cols
        )

    @mock.patch.object(HiveMetastoreLoader, "_check_partition_keys")
    @mock.patch.object(HiveMetastoreLoader, "_update_table_in_metastore")
    @mock.patch.object(HiveMetastoreLoader, "is_table_in_metastore")
    @mock.patch.object(HiveMetastoreLoader, "create_table")
    def test_update_metastore_with_new_table(
        self,
        mocked_create_table,
        mocked_is_table_in_metastore,
        mocked__update_table_in_metastore,
        mocked__check_partition_keys,
        hive_metastore_loader,
    ):
        # arrange
        table_schema = "<table_schema>"
        database_name = "<db_name>"
        table_name = "<tb_name>"
        format_info = "<format_info>"
        database_location = "<location>"
        source_schema = "<source schema>"
        partition_keys = "<partition_keys>"

        mocked_is_table_in_metastore.return_value = False

        # act
        hive_metastore_loader.update_metastore(
            database_name,
            table_name,
            database_location,
            table_schema,
            partition_keys,
            format_info,
            source_schema,
        )

        # assert
        mocked__update_table_in_metastore.assert_not_called()
        mocked__check_partition_keys.assert_not_called()
        mocked_is_table_in_metastore.assert_called_once_with(database_name, table_name)
        mocked_create_table.assert_called_once_with(
            database_name,
            table_name,
            database_location + table_name,
            table_schema,
            partition_keys,
            format_info,
        )

    @pytest.mark.parametrize("partition_values_list", [None, [], False])
    @mock.patch.object(PartitionBuilder, "build")
    def test_add_partitions_to_table_without_partition(
        self, mocked_partition_builder, partition_values_list, hive_metastore_loader
    ):
        # arrange
        database_name = "<db_name>"
        table_name = "<table_name>"

        # assert
        with raises(ValueError):
            # act
            hive_metastore_loader.add_partitions_to_table(
                database_name, table_name, partition_values_list
            )

        mocked_partition_builder.assert_not_called()
        hive_metastore_loader.hive_metastore_service.add_partitions_to_table.assert_not_called()

    @pytest.mark.parametrize(
        "partition_values_list, expected_builds",
        [
            ([["2020", "01", "30"], ["2020", "01", "31"]], 2),
            ([["2020", "01", "30"], ["2020", "01", "31"]], 2),
            ([["2020", "01", "30"]], 1),
        ],
    )
    @mock.patch.object(PartitionBuilder, "build")
    def test_add_partitions_to_table(
        self,
        mocked_partition_builder,
        partition_values_list,
        expected_builds,
        hive_metastore_loader,
    ):
        # arrange
        database_name = "<db_name>"
        table_name = "<table_name>"

        # act
        hive_metastore_loader.add_partitions_to_table(
            database_name, table_name, partition_values_list
        )

        # assert
        hive_metastore_loader.hive_metastore_service.add_partitions_to_table.assert_called_once()
        assert mocked_partition_builder.call_count == expected_builds

    @mock.patch.object(HiveMetastoreLoader, "_get_partitions_difference")
    def test_update_table_partitions_with_partitions(
        self, mocked__get_partitions_difference, hive_metastore_loader
    ):
        # arrange
        database_name = "<database_name>"
        table_name = "<table_name>"
        partition_values = "<partition_values>"

        mocked_ms_part_values = Mock()
        hive_metastore_loader.hive_metastore_service.get_partition_values.return_value = (
            mocked_ms_part_values
        )

        added = [1, 2, 3]
        dropped = [4, 5, 6]
        mocked__get_partitions_difference.return_value = added, dropped

        # act
        hive_metastore_loader.update_table_partitions(
            database_name, table_name, partition_values
        )

        # assert
        hive_metastore_loader.hive_metastore_service.get_partition_values.assert_called_once_with(
            database_name, table_name
        )
        mocked__get_partitions_difference.assert_called_once_with(
            database_name, table_name, partition_values, mocked_ms_part_values
        )
        hive_metastore_loader.hive_metastore_service.drop_partitions_from_table.assert_called_once_with(
            database_name, table_name, dropped
        )
        hive_metastore_loader.hive_metastore_service.add_partitions_to_table.assert_called_once_with(
            database_name, table_name, added
        )

    @mock.patch.object(HiveMetastoreLoader, "_get_partitions_difference")
    def test_update_table_partitions_without_partitions(
        self, mocked__get_partitions_difference, hive_metastore_loader
    ):
        # arrange
        database_name = "<database_name>"
        table_name = "<table_name>"
        partition_values = []

        mocked_ms_part_values = []
        hive_metastore_loader.hive_metastore_service.get_partition_values.return_value = (
            mocked_ms_part_values
        )

        mocked__get_partitions_difference.return_value = [], []

        # act
        hive_metastore_loader.update_table_partitions(
            database_name, table_name, partition_values
        )

        # assert
        hive_metastore_loader.hive_metastore_service.get_partition_values.assert_called_once_with(
            database_name, table_name
        )
        mocked__get_partitions_difference.assert_called_once_with(
            database_name, table_name, partition_values, mocked_ms_part_values
        )
        hive_metastore_loader.hive_metastore_service.drop_partitions_from_table.assert_not_called()
        hive_metastore_loader.hive_metastore_service.add_partitions_to_table.assert_not_called()

    @pytest.mark.parametrize(
        "spark_partition_values, metastore_partition_values, expected_added_partitions, expected_removed_partitions",
        [
            (  # Case 1 - added
                [["2020", "1", "1"], ["2020", "1", "2"]],
                [],
                [
                    PartitionBuilder(
                        values=["2020", "1", "1"], db_name=mock.ANY, table_name=mock.ANY
                    ).build(),
                    PartitionBuilder(
                        values=["2020", "1", "2"], db_name=mock.ANY, table_name=mock.ANY
                    ).build(),
                ],
                [],
            ),
            (  # Case 2 - dropṕed
                [["2020", "1", "1"]],
                [["2020", "1", "1"], ["2020", "1", "2"]],
                [],
                [["2020", "1", "2"]],
            ),
            (  # Case 3 - added & dropped
                [["2000", "2", "1"], ["2000", "2", "2"]],
                [["1999", "10", "11"], ["1999", "10", "12"]],
                [
                    PartitionBuilder(
                        values=["2000", "2", "1"], db_name=mock.ANY, table_name=mock.ANY
                    ).build(),
                    PartitionBuilder(
                        values=["2000", "2", "2"], db_name=mock.ANY, table_name=mock.ANY
                    ).build(),
                ],
                [["1999", "10", "11"], ["1999", "10", "12"]],
            ),
            (  # Case 4 - metastores synced
                [["2001", "2", "1"], ["2001", "2", "2"]],
                [["2001", "2", "1"], ["2001", "2", "2"]],
                [],
                [],
            ),
            ([], [], [], []),  # Case 5 - no partitions
        ],
    )
    def test__get_partitions_difference(
        self,
        spark_partition_values,
        metastore_partition_values,
        expected_added_partitions,
        expected_removed_partitions,
        hive_metastore_loader,
    ):
        # act
        added_partitions, removed_partitions = hive_metastore_loader._get_partitions_difference(
            mock.ANY, mock.ANY, spark_partition_values, metastore_partition_values
        )

        # assert
        assert added_partitions == expected_added_partitions
        assert removed_partitions == expected_removed_partitions

    def test__check_partition_keys_with_synced_metastores(self, hive_metastore_loader):
        # arrange
        database_name = "<database_name>"
        table_name = "<table_name>"
        source_table_partition_keys = ["key1", "key2", "key3", "key4"]

        mocked_hive_pkeys = ["key1", "key2", "key3", "key4"]
        hive_metastore_loader.hive_metastore_service.get_partition_keys_names.return_value = (
            mocked_hive_pkeys
        )

        # act
        hive_metastore_loader._check_partition_keys(
            database_name, table_name, source_table_partition_keys
        )

        # assert
        hive_metastore_loader.hive_metastore_service.get_partition_keys_names.assert_called_once_with(
            database_name, table_name
        )

    def test__check_partition_keys_with_diverging_keys(self, hive_metastore_loader):
        # arrange
        database_name = "<database_name>"
        table_name = "<table_name>"
        source_table_partition_keys = ["key1", "key2", "key3", "key4"]

        mocked_hive_pkeys = ["key1", "key2", "key3"]
        hive_metastore_loader.hive_metastore_service.get_partition_keys_names.return_value = (
            mocked_hive_pkeys
        )

        # assert
        with raises(ValueError):
            # act
            hive_metastore_loader._check_partition_keys(
                database_name, table_name, source_table_partition_keys
            )

        hive_metastore_loader.hive_metastore_service.get_partition_keys_names.assert_called_once_with(
            database_name, table_name
        )
