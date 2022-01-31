from collections import OrderedDict
from unittest import mock
from unittest.mock import Mock

import pytest
from hive_metastore_client.builders import ColumnBuilder
from hive_metastore_client.builders import PartitionBuilder
from pytest import raises

from bietlejuice.jobs.composer.loaders import HiveMetastoreLoader


class TestHiveMetastoreLoader:
    @mock.patch.object(HiveMetastoreLoader, "update_table")
    @mock.patch.object(HiveMetastoreLoader, "_partition_keys_match")
    @mock.patch.object(HiveMetastoreLoader, "_get_table_schema_changes")
    @mock.patch.object(HiveMetastoreLoader, "_is_table_in_metastore")
    @mock.patch.object(HiveMetastoreLoader, "create_table")
    def test_sync_metastore_for_new_table(
        self,
        mocked_create_table,
        mocked__is_table_in_metastore,
        mocked__get_table_schema_changes,
        mocked__partition_keys_match,
        mocked_update_table,
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

        mocked__is_table_in_metastore.return_value = False

        # act
        hive_metastore_loader.sync_metastore(
            database_name,
            table_name,
            database_location,
            table_schema,
            partition_keys,
            format_info,
            source_schema,
        )

        # assert
        mocked__is_table_in_metastore.assert_called_once_with(database_name, table_name)
        mocked__get_table_schema_changes.assert_not_called()
        mocked__partition_keys_match.assert_not_called()
        mocked_update_table.assert_not_called()
        mocked_create_table.assert_called_once_with(
            database_name,
            table_name,
            database_location + table_name,
            table_schema,
            partition_keys,
            format_info,
        )

    @mock.patch.object(HiveMetastoreLoader, "update_table")
    @mock.patch.object(HiveMetastoreLoader, "_partition_keys_match")
    @mock.patch.object(HiveMetastoreLoader, "_get_table_schema_changes")
    @mock.patch.object(HiveMetastoreLoader, "_is_table_in_metastore")
    @mock.patch.object(HiveMetastoreLoader, "create_table")
    def test_sync_metastore_for_existing_table_with_no_changes(
        self,
        mocked_create_table,
        mocked__is_table_in_metastore,
        mocked__get_table_schema_changes,
        mocked__partition_keys_match,
        mocked_update_table,
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

        mocked__is_table_in_metastore.return_value = True
        mocked__get_table_schema_changes.return_value = {}
        mocked__partition_keys_match.return_value = True

        # act
        hive_metastore_loader.sync_metastore(
            database_name,
            table_name,
            database_location,
            table_schema,
            partition_keys,
            format_info,
            source_schema,
        )

        # assert
        mocked__is_table_in_metastore.assert_called_once_with(database_name, table_name)
        mocked__get_table_schema_changes.assert_called_once_with(
            database_name, table_name, source_schema
        )
        mocked__partition_keys_match.assert_called_once_with(
            database_name, table_name, partition_keys
        )
        mocked_update_table.assert_not_called()
        mocked_create_table.assert_not_called()

    @mock.patch.object(HiveMetastoreLoader, "update_table")
    @mock.patch.object(HiveMetastoreLoader, "_partition_keys_match")
    @mock.patch.object(HiveMetastoreLoader, "_get_table_schema_changes")
    @mock.patch.object(HiveMetastoreLoader, "_is_table_in_metastore")
    @mock.patch.object(HiveMetastoreLoader, "create_table")
    def test_sync_metastore_for_existing_table_with_changes(
        self,
        mocked_create_table,
        mocked__is_table_in_metastore,
        mocked__get_table_schema_changes,
        mocked__partition_keys_match,
        mocked_update_table,
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

        mocked__is_table_in_metastore.return_value = True
        schema_changes = {"added_columns": ["a"]}
        mocked__get_table_schema_changes.return_value = schema_changes
        mocked__partition_keys_match.return_value = True

        # act
        hive_metastore_loader.sync_metastore(
            database_name,
            table_name,
            database_location,
            table_schema,
            partition_keys,
            format_info,
            source_schema,
        )

        # assert
        mocked__is_table_in_metastore.assert_called_once_with(database_name, table_name)
        mocked__get_table_schema_changes.assert_called_once_with(
            database_name, table_name, source_schema
        )
        mocked__partition_keys_match.assert_called_once_with(
            database_name, table_name, partition_keys
        )
        mocked_update_table.assert_called_once_with(
            database_name,
            table_name,
            database_location + table_name,
            table_schema,
            partition_keys,
            format_info,
            schema_changes,
        )
        mocked_create_table.assert_not_called()

    @pytest.mark.parametrize(
        "added_cols, removed_cols, changes",
        [
            (
                ["a", "b"],
                ["c", "d"],
                {"added_columns": ["a", "b"], "removed_columns": ["c", "d"]},
            ),
            ([], [], {}),
        ],
    )
    @mock.patch.object(HiveMetastoreLoader, "_get_tables_difference")
    def test__get_table_schema_changes(
        self,
        mocked__get_tables_difference,
        hive_metastore_loader,
        added_cols,
        removed_cols,
        changes,
    ):
        # arrange
        database_name = "datalake_ebdb_clean_prod"
        table_name = "house"
        source_columns = OrderedDict([("some_col_name", "type")])

        hive_table_columns = {"name": "type"}
        hive_metastore_loader.hive_metastore_service.get_table_columns.return_value = (
            hive_table_columns
        )

        mocked__get_tables_difference.return_value = added_cols, removed_cols

        # act
        returned_value = hive_metastore_loader._get_table_schema_changes(
            database_name, table_name, source_columns
        )

        # assert
        assert returned_value == changes
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
        returned_value = hive_metastore_loader._is_table_in_metastore(
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

    @mock.patch.object(HiveMetastoreLoader, "_map_partition_values_difference")
    def test_update_table_partitions_with_partitions(
        self, mocked__map_partition_values_difference, hive_metastore_loader
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
        mocked__map_partition_values_difference.return_value = added, dropped

        # act
        hive_metastore_loader.update_table_partitions(
            database_name, table_name, partition_values
        )

        # assert
        hive_metastore_loader.hive_metastore_service.get_partition_values.assert_called_once_with(
            database_name, table_name
        )
        mocked__map_partition_values_difference.assert_called_once_with(
            database_name, table_name, partition_values, mocked_ms_part_values
        )
        hive_metastore_loader.hive_metastore_service.drop_partitions_from_table.assert_called_once_with(
            database_name, table_name, dropped
        )
        hive_metastore_loader.hive_metastore_service.add_partitions_to_table.assert_called_once_with(
            database_name, table_name, added
        )

    @mock.patch.object(HiveMetastoreLoader, "_map_partition_values_difference")
    def test_update_table_partitions_without_partitions(
        self, mocked__map_partition_values_difference, hive_metastore_loader
    ):
        # arrange
        database_name = "<database_name>"
        table_name = "<table_name>"
        partition_values = []

        mocked_ms_part_values = []
        hive_metastore_loader.hive_metastore_service.get_partition_values.return_value = (
            mocked_ms_part_values
        )

        mocked__map_partition_values_difference.return_value = [], []

        # act
        hive_metastore_loader.update_table_partitions(
            database_name, table_name, partition_values
        )

        # assert
        hive_metastore_loader.hive_metastore_service.get_partition_values.assert_called_once_with(
            database_name, table_name
        )
        mocked__map_partition_values_difference.assert_called_once_with(
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
        added_partitions, removed_partitions = hive_metastore_loader._map_partition_values_difference(
            mock.ANY, mock.ANY, spark_partition_values, metastore_partition_values
        )

        # assert
        assert added_partitions == expected_added_partitions
        assert removed_partitions == expected_removed_partitions

    @pytest.mark.parametrize(
        "source_pkeys, hive_pkeys, expected_value",
        [
            (["key1", "key2", "key3"], ["key1", "key2", "key3"], True),
            (["key1", "key2"], ["key1"], False),
        ],
    )
    def test__partition_keys_match(
        self, hive_metastore_loader, source_pkeys, hive_pkeys, expected_value
    ):
        # arrange
        database_name = "<database_name>"
        table_name = "<table_name>"

        hive_metastore_loader.hive_metastore_service.get_partition_keys.return_value = (
            hive_pkeys
        )

        # act
        returned_value = hive_metastore_loader._partition_keys_match(
            database_name, table_name, source_pkeys
        )

        # assert
        assert returned_value == expected_value
        hive_metastore_loader.hive_metastore_service.get_partition_keys.assert_called_once_with(
            database_name, table_name
        )

    def test__is_table_partitioned(self, hive_metastore_loader):
        # arrange
        database_name = "foo"
        table_name = "bar"
        expected_return = ["p1"]
        hive_metastore_loader.hive_metastore_service.get_partition_keys.return_value = (
            expected_return
        )

        # act
        returned_value = hive_metastore_loader._is_table_partitioned(
            database_name, table_name
        )

        # assert
        assert returned_value == expected_return
        hive_metastore_loader.hive_metastore_service.get_partition_keys.assert_called_once_with(
            database_name, table_name
        )

    def test__update_table_in_metastore(self, hive_metastore_loader):
        # arrange
        database_name = "db_bla"
        table_name = "table_x"
        schema_changes = {"added_columns": [Mock()], "removed_columns": ["x", "y"]}

        # act
        hive_metastore_loader._update_table_in_metastore(
            database_name, table_name, schema_changes
        )

        # assert
        hive_metastore_loader.hive_metastore_service.drop_columns_from_table.assert_called_once_with(
            database_name, table_name, schema_changes.get("removed_columns")
        )
        hive_metastore_loader.hive_metastore_service.add_columns_to_table.assert_called_once_with(
            database_name, table_name, schema_changes.get("added_columns")
        )

    @mock.patch.object(HiveMetastoreLoader, "_update_table_in_metastore")
    @mock.patch.object(HiveMetastoreLoader, "_is_table_partitioned")
    def test_update_table_for_non_partitioned_table(
        self,
        mocked__is_table_partitioned,
        mocked__update_table_in_metastore,
        hive_metastore_loader,
    ):
        # arrange
        table_schema = "<table_schema>"
        database_name = "<db_name>"
        table_name = "<tb_name>"
        format_info = "<format_info>"
        table_location = "<location>"
        source_partition_keys = []
        schema_changes = "<schema changes>"

        mocked__is_table_partitioned.return_value = False

        # act
        hive_metastore_loader.update_table(
            database_name,
            table_name,
            table_location,
            table_schema,
            source_partition_keys,
            format_info,
            schema_changes,
        )

        # assert
        hive_metastore_loader.hive_metastore_service.drop_table.assert_not_called()
        hive_metastore_loader.hive_metastore_service.create_external_table.assert_not_called()
        mocked__update_table_in_metastore.assert_called_once_with(
            database_name, table_name, schema_changes
        )

    @pytest.mark.parametrize(
        "source_partition_keys, is_table_partitioned_in_hive",
        [
            (["a", "b"], False),  # table partitioned in spark (partitions added)
            ([], True),  # table partitioned in hive (partitions removed)
            (["a"], True),  # partitions updated
        ],
    )
    @mock.patch.object(HiveMetastoreLoader, "_update_table_in_metastore")
    @mock.patch.object(HiveMetastoreLoader, "_is_table_partitioned")
    def test_update_table_for_partitioned_table_in_spark(
        self,
        mocked__is_table_partitioned,
        mocked__update_table_in_metastore,
        source_partition_keys,
        is_table_partitioned_in_hive,
        hive_metastore_loader,
    ):
        # arrange
        table_schema = "<table_schema>"
        database_name = "<db_name>"
        table_name = "<tb_name>"
        format_info = "<format_info>"
        table_location = "<location>"
        schema_changes = "<schema changes>"

        mocked__is_table_partitioned.return_value = is_table_partitioned_in_hive

        # act
        hive_metastore_loader.update_table(
            database_name,
            table_name,
            table_location,
            table_schema,
            source_partition_keys,
            format_info,
            schema_changes,
        )

        # assert
        hive_metastore_loader.hive_metastore_service.drop_table.assert_called_once_with(
            database_name, table_name
        )
        hive_metastore_loader.hive_metastore_service.create_external_table.assert_called_once_with(
            database_name,
            table_name,
            table_location,
            table_schema,
            source_partition_keys,
            format_info,
        )
        mocked__update_table_in_metastore.assert_not_called()
