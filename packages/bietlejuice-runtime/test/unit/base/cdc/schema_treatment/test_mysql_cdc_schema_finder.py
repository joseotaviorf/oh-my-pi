from unittest import mock

import pytest

from bietlejuice.base.cdc.schema_treatment.mysql_cdc_schema_finder import (
    MySqlCdcSchemaFinder,
)

EXPECTED_DEFINITION = {
    "primaryKeyColumnNames": ["column1", "column2"],
    "columns": [
        {
            "name": "column1",
            "typeName": "VARCHAR",
            "length": 255,
            "scale": None,
        },
        {
            "name": "column2",
            "typeName": "DECIMAL",
            "length": 11,
            "scale": 2,
        },
    ],
}


class TestMySqlCdcSchemaFinder:
    @pytest.fixture
    def mysql_consumer(self):
        consumer = mock.MagicMock()
        consumer.get_table_primary_keys.return_value = ["column1", "column2"]
        consumer.get_table_primary_keys_on_driver.return_value = [
            "column1",
            "column2",
        ]
        consumer.get_table_schema_on_driver.return_value = [
            {"col_name": "column1", "col_type": "varchar(255)"},
            {"col_name": "column2", "col_type": "decimal(11,2)"},
        ]
        schema_df = mock.MagicMock()
        renamed = (
            schema_df.withColumnRenamed.return_value.withColumnRenamed.return_value
        )
        renamed.collect.return_value = [
            mock.MagicMock(
                asDict=mock.MagicMock(
                    return_value={"name": "column1", "typeName": "varchar(255)"}
                )
            ),
            mock.MagicMock(
                asDict=mock.MagicMock(
                    return_value={"name": "column2", "typeName": "decimal(11,2)"}
                )
            ),
        ]
        consumer.get_table_schema.return_value = schema_df
        return consumer

    def test_find_latest_table_definition_uses_spark_jdbc_by_default(
        self, mysql_consumer
    ):
        # Arrange
        schema_finder = MySqlCdcSchemaFinder(mysql_consumer)

        # Act
        result = schema_finder.find_latest_table_definition("dummy_table")

        # Assert
        assert result == EXPECTED_DEFINITION
        mysql_consumer.get_table_primary_keys.assert_called_once_with("dummy_table")
        mysql_consumer.get_table_schema.assert_called_once_with("dummy_table")
        mysql_consumer.get_table_primary_keys_on_driver.assert_not_called()
        mysql_consumer.get_table_schema_on_driver.assert_not_called()

    def test_find_latest_table_definition_uses_driver_metadata_for_navent(
        self, mysql_consumer
    ):
        # Arrange
        schema_finder = MySqlCdcSchemaFinder(mysql_consumer, use_driver_jdbc=True)

        # Act
        result = schema_finder.find_latest_table_definition("dummy_table")

        # Assert
        assert result == EXPECTED_DEFINITION
        mysql_consumer.get_table_primary_keys_on_driver.assert_called_once_with(
            "dummy_table"
        )
        mysql_consumer.get_table_schema_on_driver.assert_called_once_with("dummy_table")
        mysql_consumer.get_table_primary_keys.assert_not_called()
        mysql_consumer.get_table_schema.assert_not_called()
