import pytest
from unittest import mock
from unittest.mock import MagicMock

from bietlejuice.base.cdc.schema_treatment.postgres_cdc_schema_treatment import (
    PostgresCdcSchemaTreatment,
)


def _make_column(name, type_name, length=None, scale=None):
    return {
        "name": name,
        "typeName": type_name,
        "length": length,
        "scale": scale,
    }


class TestPostgresCdcSchemaTreatmentTypeMapping:
    """
    Guards the type mapping that translates Postgres
    `information_schema.columns.data_type` values into Spark/Delta types.
    Missing entries here cause CDC tables to keep the JSON-inferred type
    (often `string` for `bigint` FKs), which is then locked in forever by
    `_cast_differing_types`.
    """

    @pytest.fixture
    def treatment(self):
        return PostgresCdcSchemaTreatment(
            schema_finder=MagicMock(),
            datalake_table_schema="datalake_layer_test",
            transactional_datatype_overrides={},
            database_column_alias={},
        )

    @pytest.fixture
    def mock_dataframe(self):
        df = MagicMock()
        df.columns = [
            "small_col",
            "int_col",
            "big_col",
            "real_col",
            "double_col",
            "untyped_col",
        ]
        df.withColumn.return_value = df
        return df

    def test_type_mapping_covers_expected_postgres_numeric_types(self, treatment):
        assert treatment.TYPE_MAPPING == {
            "smallint": "int",
            "integer": "int",
            "bigint": "bigint",
            "real": "float",
            "double precision": "double",
        }

    @pytest.mark.parametrize(
        "postgres_type, spark_type",
        [
            ("smallint", "int"),
            ("integer", "int"),
            ("bigint", "bigint"),
            ("real", "float"),
            ("double precision", "double"),
        ],
    )
    @mock.patch("bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment.col")
    def test_map_column_types_casts_known_postgres_types(
        self,
        mock_col,
        treatment,
        mock_dataframe,
        postgres_type,
        spark_type,
    ):
        mock_col_instance = MagicMock()
        mock_col.return_value = mock_col_instance

        latest_table_change = {
            "columns": [_make_column("big_col", postgres_type)],
        }

        treatment._map_column_types(mock_dataframe, latest_table_change)

        mock_col_instance.cast.assert_called_once_with(spark_type)

    @mock.patch("bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment.col")
    def test_map_column_types_skips_unknown_postgres_types(
        self, mock_col, treatment, mock_dataframe
    ):
        latest_table_change = {
            "columns": [_make_column("untyped_col", "uuid")],
        }

        treatment._map_column_types(mock_dataframe, latest_table_change)

        mock_col.assert_not_called()
        mock_dataframe.withColumn.assert_not_called()
