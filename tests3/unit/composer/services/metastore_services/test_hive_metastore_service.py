from collections import OrderedDict

import mock
import pytest
from hive_metastore_client.builders import ColumnBuilder
from mock import Mock

from bietlejuice.jobs.composer.base.hive import TableStorageDescriptorEnum
from bietlejuice.jobs.composer.services.metastore_services import HiveMetastoreService


class TestHiveMetastoreService:
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
        table_schema = ""
        partition_cols = ""
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

        # Mocking the conn inside with statement
        mocked_open_conn = Mock()
        mocked_client = Mock()
        mocked_client.return_value = mocked_open_conn

        hive_metastore_service._client.__enter__ = mocked_client
        hive_metastore_service._client.__exit__ = Mock()

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
            [mock.call(table_schema), mock.call(partition_cols)]
        )
        mocked_serde_info_builder.assert_called_once_with(
            serialization_lib=format_info.serde_lib
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
        mocked_open_conn.create_table.assert_called_once_with(mocked_table.build())

    @pytest.mark.parametrize(
        "table_columns, expected_return",
        [
            (
                OrderedDict([("id", "int"), ("name", "string"), ("is_active", "bool")]),
                [
                    ColumnBuilder(name="id", type="int", comment=None).build(),
                    ColumnBuilder(name="name", type="string", comment=None).build(),
                    ColumnBuilder(name="is_active", type="bool", comment=None).build(),
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

    def test_get_table_schema(self, hive_metastore_service):
        # arrange
        database_name = "datalake_ebdb_clean_prod"
        table_name = "user"
        mocked_schema = "<list of FieldSchema>"

        # Mocking the conn inside with statement
        mocked_open_conn = Mock()
        mocked_open_conn.get_schema.return_value = mocked_schema

        mocked_client = Mock()
        mocked_client.return_value = mocked_open_conn

        hive_metastore_service._client.__enter__ = mocked_client

        # act
        returned_value = hive_metastore_service.get_table_schema(
            database_name, table_name
        )

        # assert
        assert returned_value == mocked_schema
        mocked_open_conn.get_schema.assert_called_once_with(database_name, table_name)

    @mock.patch.object(HiveMetastoreService, "_get_columns_from_schema")
    @mock.patch.object(HiveMetastoreService, "get_table_schema")
    def test_get_table_columns(
        self,
        mocked_get_table_schema,
        mocked__get_columns_from_schema,
        hive_metastore_service,
    ):
        # arrange
        database_name = "datalake_ebdb_clean_prod"
        table_name = "contract"

        mocked_table_schema = "<table schema>"
        mocked_get_table_schema.return_value = mocked_table_schema

        mocked_columns = "<columns dictionary>"
        mocked__get_columns_from_schema.return_value = mocked_columns

        # act
        returned_value = hive_metastore_service.get_table_columns(
            database_name, table_name
        )

        # assert
        assert returned_value == mocked_columns
        mocked_get_table_schema.assert_called_once_with(database_name, table_name)
        mocked__get_columns_from_schema.assert_called_once_with(mocked_table_schema)

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
        returned_value = hive_metastore_service._get_columns_from_schema(table_schema)

        # assert
        assert returned_value == expected_return
