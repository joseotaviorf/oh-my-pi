import pytest
from unittest import mock
from bietlejuice.base.spark import BaseSparkContext
from bietlejuice.base.cdc.schema_treatment.postgres_cdc_schema_finder import (
    PostgresCdcSchemaFinder,
)


class TestPostgresCdcSchemaFinder:
    @pytest.fixture
    def postgres_consumer(self):
        with mock.patch(
            "bietlejuice.base.cdc.schema_treatment.postgres_cdc_schema_finder.PostgresConsumer"
        ) as postgres_consumer:
            postgres_consumer.get_table_primary_keys.return_value = [
                "column1",
                "column2",
            ]
            postgres_consumer.get_table_schema.return_value = BaseSparkContext.spark.createDataFrame(
                [("column1", "VARCHAR", 255, None), ("column2", "NUMERIC", 11, 2)],
                ["col_name", "col_type", "col_length", "col_scale"],
            )
            yield postgres_consumer

    def test_find_latest_table_definition(self, postgres_consumer):
        postgres_cdc_schema_finder = PostgresCdcSchemaFinder(postgres_consumer)
        table_name = "tabela_dummy"
        result = postgres_cdc_schema_finder.find_latest_table_definition(table_name)
        expected_result = {
            "primaryKeyColumnNames": ["column1", "column2"],
            "columns": [
                {
                    "name": "column1",
                    "typeName": "VARCHAR",
                    "length": 255,
                    "scale": None,
                },
                {"name": "column2", "typeName": "NUMERIC", "length": 11, "scale": 2},
            ],
        }
        assert result == expected_result
        postgres_consumer.get_table_primary_keys.assert_called_once_with(table_name)
        postgres_consumer.get_table_schema.assert_called_once_with(table_name)
