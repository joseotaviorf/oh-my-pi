from collections import OrderedDict

import mock
import pytest
from hive_metastore_client.builders import ColumnBuilder
from hive_metastore_client.builders import PartitionBuilder
from mock import Mock

from bietlejuice.jobs.composer.base.hive import TableStorageDescriptorEnum
from bietlejuice.jobs.composer.services.metastore_services import HiveMetastoreService


class TestHiveMetastoreService:
    @staticmethod
    def _mock_open_connection_helper(hive_metastore_service):
        # Mocking the conn inside `with` statement
        mocked_open_conn = Mock()

        mocked_client = Mock()
        mocked_client.return_value = mocked_open_conn

        hive_metastore_service._client.__enter__ = mocked_client
        hive_metastore_service._client.__exit__ = Mock()

        return mocked_open_conn

    def test_client(self, hive_metastore_service):
        # arrange
        mocked_client = Mock()
        hive_metastore_service._client = mocked_client

        # act
        returned_value = hive_metastore_service.client

        # assert
        assert returned_value == mocked_client

    @mock.patch(
        "bietlejuice.jobs.composer.services.metastore_services.hive_metastore_service.TableBuilder"
    )
    @mock.patch(
        "bietlejuice.jobs.composer.services.metastore_services.hive_metastore_service.StorageDescriptorBuilder"
    )
    @mock.patch(
        "bietlejuice.jobs.composer.services.metastore_services.hive_metastore_service.SerDeInfoBuilder"
    )
    @mock.patch.object(HiveMetastoreService, "_build_columns_from_dict")
    def test_create_external_table(
        self,
        mocked__build_columns_from_dict,
        mocked_serde_info_builder,
        mocked_storage_desc_builder,
        mocked_table_builder,
        hive_metastore_service,
    ):
        # arrange
        db_name = "ebdb"
        table_name = "user"
        table_location = ""
        table_schema = OrderedDict(
            [("id", "int"), ("name", "string"), ("is_active", "bool")]
        )
        partition_cols = [("year", "string")]
        format_info = TableStorageDescriptorEnum.CLEAN_FORMAT.value

        mocked_cols_or_part_keys = Mock()
        mocked__build_columns_from_dict.return_value = mocked_cols_or_part_keys

        # Mocking builders
        mocked_serde_info = Mock()
        mocked_serde_info_builder.return_value = mocked_serde_info

        mocked_storage_desc = Mock()
        mocked_storage_desc_builder.return_value = mocked_storage_desc

        mocked_table = Mock()
        mocked_table_builder.return_value = mocked_table

        mocked_open_conn = self._mock_open_connection_helper(hive_metastore_service)

        # act
        hive_metastore_service.create_external_table(
            database_name=db_name,
            table_name=table_name,
            table_location=table_location,
            table_schema=table_schema,
            partition_cols=partition_cols,
            format_info=format_info,
        )

        # assert
        mocked__build_columns_from_dict.assert_has_calls(
            [mock.call(table_schema.items()), mock.call(partition_cols)]
        )
        mocked_serde_info_builder.assert_called_once_with(
            serialization_lib=format_info.serde_lib,
            parameters={"timestamp.formats": "yyyy-MM-dd'T'HH:mm:ss.SSSS'Z'"},
        )
        mocked_storage_desc_builder.assert_called_once_with(
            columns=mocked_cols_or_part_keys,
            location=table_location,
            input_format=format_info.input_format,
            output_format=format_info.output_format,
            serde_info=mocked_serde_info.build(),
        )
        mocked_table_builder.assert_called_once_with(
            table_name=table_name,
            db_name=db_name,
            owner=hive_metastore_service.DEFAULT_TABLE_OWNER,
            storage_descriptor=mocked_storage_desc.build(),
            partition_keys=mocked_cols_or_part_keys,
        )
        mocked_open_conn.create_external_table.assert_called_once_with(
            mocked_table.build()
        )

    @pytest.mark.parametrize(
        "table_columns, expected_return",
        [
            (
                [("id", "int"), ("name", "string"), ("is_active", "bool")],
                [
                    ColumnBuilder(name="id", type="int", comment=None).build(),
                    ColumnBuilder(name="name", type="string", comment=None).build(),
                    ColumnBuilder(name="is_active", type="bool", comment=None).build(),
                ],
            ),
            (
                OrderedDict([("id", "int"), ("name", "string")]).items(),
                [
                    ColumnBuilder(name="id", type="int", comment=None).build(),
                    ColumnBuilder(name="name", type="string", comment=None).build(),
                ],
            ),
            (OrderedDict([]), []),
        ],
    )
    def test__build_columns_from_dict(
        self, table_columns, expected_return, hive_metastore_service
    ):
        # act
        returned_value = hive_metastore_service._build_columns_from_dict(table_columns)

        # assert
        assert returned_value == expected_return

    def test_get_table(self, hive_metastore_service):
        # arrange
        database_name = "datalake_terminator_clean_prod"
        table_name = "user"
        mocked_table = Mock()

        mocked_open_conn = self._mock_open_connection_helper(hive_metastore_service)
        mocked_open_conn.get_table.return_value = mocked_table

        # act
        returned_value = hive_metastore_service.get_table(database_name, table_name)

        # assert
        assert returned_value == mocked_table
        mocked_open_conn.get_table.assert_called_once_with(database_name, table_name)

    def test_get_table_schema(self, hive_metastore_service):
        # arrange
        database_name = "datalake_ebdb_clean_prod"
        table_name = "user"
        mocked_schema = "<list of FieldSchema>"

        mocked_open_conn = self._mock_open_connection_helper(hive_metastore_service)
        mocked_open_conn.get_schema.return_value = mocked_schema

        # act
        returned_value = hive_metastore_service.get_table_schema(
            database_name, table_name
        )

        # assert
        assert returned_value == mocked_schema
        mocked_open_conn.get_schema.assert_called_once_with(database_name, table_name)

    def test_get_table_names(self, hive_metastore_service):
        # arrange
        database_name = "datalake_ebdb_clean_prod"
        mocked_table_names = "<list of table names>"

        mocked_open_conn = self._mock_open_connection_helper(hive_metastore_service)
        mocked_open_conn.get_all_tables.return_value = mocked_table_names

        # act
        returned_value = hive_metastore_service.get_table_names(database_name)

        # assert
        assert returned_value == mocked_table_names
        mocked_open_conn.get_all_tables.assert_called_once_with(database_name)

    @mock.patch.object(HiveMetastoreService, "_parse_field_schema")
    @mock.patch.object(HiveMetastoreService, "get_table")
    def test_get_table_columns_with_partition_keys(
        self, mocked_get_table, mocked__parse_field_schema, hive_metastore_service
    ):
        # arrange
        database_name = "datalake_ebdb_clean_prod"
        table_name = "contract"

        mocked_table = Mock()
        mocked_get_table.return_value = mocked_table

        mocked_columns = {"c1": "int", "c2": "string", "c3": "bool"}
        mocked__parse_field_schema.return_value = mocked_columns

        # act
        returned_value = hive_metastore_service.get_table_columns(
            database_name, table_name
        )

        # assert
        assert returned_value == mocked_columns
        mocked_get_table.assert_called_once_with(database_name, table_name)
        mocked__parse_field_schema.assert_called_once_with(mocked_table.sd.cols)

    @mock.patch.object(HiveMetastoreService, "_parse_field_schema")
    @mock.patch.object(HiveMetastoreService, "get_table")
    def test_get_table_columns_ignoring_partition_keys(
        self, mocked_get_table, mocked__parse_field_schema, hive_metastore_service
    ):
        # arrange
        database_name = "datalake_ebdb_clean_prod"
        table_name = "contract"

        mocked_table = Mock()
        mocked_get_table.return_value = mocked_table

        mocked_columns = {
            "c1": "int",
            "c2": "string",
            "c3": "bool",
            "pk1": "string",
            "pk2": "string",
        }
        mocked_partition_keys = {"pk1": "string", "pk2": "string"}
        mocked__parse_field_schema.side_effect = [mocked_columns, mocked_partition_keys]

        # act
        returned_value = hive_metastore_service.get_table_columns(
            database_name, table_name, ignore_partition_keys=True
        )

        # assert
        assert returned_value == {"c1": "int", "c2": "string", "c3": "bool"}
        mocked_get_table.assert_called_once_with(database_name, table_name)
        mocked__parse_field_schema.assert_has_calls(
            [mock.call(mocked_table.sd.cols), mock.call(mocked_table.partitionKeys)]
        )

    @pytest.mark.parametrize(
        "table_schema, expected_return",
        [
            (
                [
                    ColumnBuilder(name="id", type="int", comment=None).build(),
                    ColumnBuilder(name="name", type="string", comment=None).build(),
                    ColumnBuilder(name="is_active", type="bool", comment=None).build(),
                ],
                {"id": "int", "name": "string", "is_active": "bool"},
            ),
            ([], {}),
        ],
    )
    def test__get_columns_from_schema(
        self, table_schema, expected_return, hive_metastore_service
    ):
        # act
        returned_value = hive_metastore_service._parse_field_schema(table_schema)

        # assert
        assert returned_value == expected_return

    def test_add_columns_to_table(self, hive_metastore_service):
        # arrange
        database_name = "datalake_ebdb_clean_prod"
        table_name = "user"
        columns = "<list of columns to add>"

        mocked_open_conn = self._mock_open_connection_helper(hive_metastore_service)

        # act
        hive_metastore_service.add_columns_to_table(database_name, table_name, columns)

        # assert
        mocked_open_conn.add_columns_to_table.assert_called_once_with(
            database_name, table_name, columns
        )

    def test_drop_columns_from_table(self, hive_metastore_service):
        # arrange
        database_name = "datalake_ebdb_clean_prod"
        table_name = "user"
        columns = "<list of columns to remove>"

        mocked_open_conn = self._mock_open_connection_helper(hive_metastore_service)

        # act
        hive_metastore_service.drop_columns_from_table(
            database_name, table_name, columns
        )

        # assert
        mocked_open_conn.drop_columns_from_table.assert_called_once_with(
            database_name, table_name, columns
        )

    @mock.patch(
        "bietlejuice.jobs.composer.services.metastore_services.hive_metastore_service.DatabaseBuilder"
    )
    def test_create_database_if_not_exists(
        self, mocked_database_builder, hive_metastore_service
    ):
        # arrange
        db_name = "<db_name>"

        mocked_db_obj = Mock()
        mocked_database_builder.return_value = mocked_db_obj

        mocked_open_conn = self._mock_open_connection_helper(hive_metastore_service)

        # act
        hive_metastore_service.create_database(db_name)

        # assert
        mocked_database_builder.assert_called_once_with(db_name)
        mocked_open_conn.create_database_if_not_exists.assert_called_once_with(
            mocked_db_obj.build()
        )

    @pytest.mark.parametrize(
        "database_name, table_name, partition_list",
        [
            (
                "my_db_name",
                "user",
                [
                    PartitionBuilder(
                        ["2020", "12", "13"], "my_db_name", "user"
                    ).build(),
                    PartitionBuilder(
                        ["2020", "12", "14"], "my_db_name", "user"
                    ).build(),
                ],
            ),
            (
                "my_db_name",
                "house",
                [
                    PartitionBuilder(
                        ["2020", "12", "13"], "my_db_name", "house"
                    ).build(),
                    PartitionBuilder(
                        ["2020", "12", "14"], "my_db_name", "house"
                    ).build(),
                ],
            ),
        ],
    )
    def test_add_partitions_to_table(
        self, database_name, table_name, partition_list, hive_metastore_service
    ):
        # arrange
        mocked_open_conn = self._mock_open_connection_helper(hive_metastore_service)

        # act
        hive_metastore_service.add_partitions_to_table(
            database_name, table_name, partition_list
        )

        # assert
        mocked_open_conn.add_partitions_if_not_exists.assert_called_once_with(
            database_name, table_name, partition_list
        )

    def test_get_partition_keys(self, hive_metastore_service):
        # arrange
        database_name = "<database_name>"
        table_name = "<table_name>"
        mocked_partition_keys = [("a", "string"), ("c", "string"), ("c", "string")]

        mocked_open_conn = self._mock_open_connection_helper(hive_metastore_service)
        mocked_open_conn.get_partition_keys.return_value = mocked_partition_keys

        # act
        returned_value = hive_metastore_service.get_partition_keys(
            database_name, table_name
        )

        # assert
        assert returned_value == mocked_partition_keys
        mocked_open_conn.get_partition_keys.assert_called_once_with(
            database_name, table_name
        )

    def test_get_partition_keys_names(self, hive_metastore_service):
        # arrange
        database_name = "<database_name>"
        table_name = "<table_name>"
        mocked_partition_keys = ["a", "b", "c"]

        mocked_open_conn = self._mock_open_connection_helper(hive_metastore_service)
        mocked_open_conn.get_partition_keys_names.return_value = mocked_partition_keys

        # act
        returned_value = hive_metastore_service.get_partition_keys_names(
            database_name, table_name
        )

        # assert
        assert returned_value == mocked_partition_keys
        mocked_open_conn.get_partition_keys_names.assert_called_once_with(
            database_name, table_name
        )

    def test_get_partition_values(self, hive_metastore_service):
        # arrange
        database_name = "<database_name>"
        table_name = "<table_name>"
        mocked_partition_values = [["a"], ["b"], ["c"]]

        mocked_open_conn = self._mock_open_connection_helper(hive_metastore_service)
        mocked_open_conn.get_partition_values_from_table.return_value = (
            mocked_partition_values
        )

        # act
        returned_value = hive_metastore_service.get_partition_values(
            database_name, table_name
        )

        # assert
        assert returned_value == mocked_partition_values
        mocked_open_conn.get_partition_values_from_table.assert_called_once_with(
            database_name, table_name
        )

    def test_drop_partitions_from_table(self, hive_metastore_service):
        # arrange
        database_name = "<database_name>"
        table_name = "<table_name>"
        partition_list = Mock()

        mocked_open_conn = self._mock_open_connection_helper(hive_metastore_service)

        # act
        hive_metastore_service.drop_partitions_from_table(
            database_name, table_name, partition_list
        )

        # assert
        mocked_open_conn.bulk_drop_partitions.assert_called_once_with(
            database_name, table_name, partition_list
        )

    def test_drop_table(self, hive_metastore_service):
        # arrange
        database_name = "datalake_bla"
        table_name = "foo_table"

        mocked_open_conn = self._mock_open_connection_helper(hive_metastore_service)

        # act
        hive_metastore_service.drop_table(database_name, table_name)

        # assert
        mocked_open_conn.drop_table.assert_called_once_with(
            database_name, table_name
        )