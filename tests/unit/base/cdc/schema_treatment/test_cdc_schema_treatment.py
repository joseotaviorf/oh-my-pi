import pytest
from unittest import mock
from unittest.mock import MagicMock

from bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment import (
    CdcSchemaTreatment,
)


class ConcreteCdcSchemaTreatment(CdcSchemaTreatment):
    """Minimal concrete subclass to test the abstract base class methods."""

    TYPE_MAPPING = {}

    def __init__(self, transactional_datatype_overrides=None):
        self.transactional_datatype_overrides = transactional_datatype_overrides or {}

    def treat_dataframe(self, table_name, transactional_dataframe):
        return transactional_dataframe


def _make_column(name, type_name, length=None, scale=None):
    return {
        "name": name,
        "typeName": type_name,
        "length": length,
        "scale": scale,
    }


class TestTreatDecimalColumns:
    @pytest.fixture
    def treatment(self):
        return ConcreteCdcSchemaTreatment()

    @pytest.fixture
    def mock_dataframe(self):
        df = MagicMock()
        df.columns = ["amount", "quantity", "overridden_col", "non_decimal"]
        df.withColumn.return_value = df
        return df

    @mock.patch("bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment.col")
    def test_normal_precision_casts_as_reported(
        self, mock_col, treatment, mock_dataframe
    ):
        mock_col_instance = MagicMock()
        mock_col.return_value = mock_col_instance

        latest_table_change = {"columns": [_make_column("amount", "NUMERIC", 10, 2)]}

        treatment._treat_decimal_columns(mock_dataframe, latest_table_change)

        mock_col_instance.cast.assert_called_once_with("decimal(10, 2)")

    @pytest.mark.parametrize(
        "length, scale, expected_type",
        [
            (40, 10, "decimal(38, 10)"),
            (50, 20, "decimal(38, 20)"),
            (100, 5, "decimal(38, 5)"),
            (38, 10, "decimal(38, 10)"),
            (39, 18, "decimal(38, 18)"),
        ],
        ids=[
            "precision_40_capped_to_38",
            "precision_50_capped_to_38",
            "precision_100_capped_to_38",
            "precision_38_unchanged",
            "precision_39_capped_to_38",
        ],
    )
    @mock.patch("bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment.col")
    def test_precision_exceeding_max_is_capped(
        self, mock_col, treatment, mock_dataframe, length, scale, expected_type
    ):
        mock_col_instance = MagicMock()
        mock_col.return_value = mock_col_instance

        latest_table_change = {
            "columns": [_make_column("amount", "NUMERIC", length, scale)]
        }

        treatment._treat_decimal_columns(mock_dataframe, latest_table_change)

        mock_col_instance.cast.assert_called_once_with(expected_type)

    @pytest.mark.parametrize(
        "length, scale",
        [
            (None, 10),
            (10, None),
            (None, None),
        ],
        ids=["null_length", "null_scale", "both_null"],
    )
    @mock.patch("bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment.col")
    def test_null_precision_or_scale_uses_fallback(
        self, mock_col, treatment, mock_dataframe, length, scale
    ):
        mock_col_instance = MagicMock()
        mock_col.return_value = mock_col_instance

        latest_table_change = {
            "columns": [_make_column("amount", "DECIMAL", length, scale)]
        }

        treatment._treat_decimal_columns(mock_dataframe, latest_table_change)

        mock_col_instance.cast.assert_called_once_with("decimal(38, 18)")

    @mock.patch("bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment.col")
    def test_columns_in_overrides_are_skipped(self, mock_col, mock_dataframe):
        treatment = ConcreteCdcSchemaTreatment(
            transactional_datatype_overrides={"overridden_col": "DECIMAL(38, 10)"}
        )
        latest_table_change = {
            "columns": [
                _make_column("overridden_col", "NUMERIC", 40, 10),
            ]
        }

        treatment._treat_decimal_columns(mock_dataframe, latest_table_change)

        mock_col.assert_not_called()
        mock_dataframe.withColumn.assert_not_called()

    @mock.patch("bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment.col")
    def test_non_decimal_columns_are_skipped(self, mock_col, treatment, mock_dataframe):
        latest_table_change = {
            "columns": [
                _make_column("non_decimal", "varchar", 255, None),
                _make_column("non_decimal", "integer", None, None),
            ]
        }

        treatment._treat_decimal_columns(mock_dataframe, latest_table_change)

        mock_col.assert_not_called()
        mock_dataframe.withColumn.assert_not_called()

    @mock.patch("bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment.col")
    def test_column_not_in_dataframe_is_skipped(
        self, mock_col, treatment, mock_dataframe
    ):
        latest_table_change = {
            "columns": [
                _make_column("missing_column", "NUMERIC", 10, 2),
            ]
        }

        treatment._treat_decimal_columns(mock_dataframe, latest_table_change)

        mock_col.assert_not_called()
        mock_dataframe.withColumn.assert_not_called()

    @mock.patch("bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment.col")
    def test_scale_capped_when_exceeds_capped_precision(
        self, mock_col, treatment, mock_dataframe
    ):
        mock_col_instance = MagicMock()
        mock_col.return_value = mock_col_instance

        latest_table_change = {"columns": [_make_column("amount", "NUMERIC", 40, 39)]}

        treatment._treat_decimal_columns(mock_dataframe, latest_table_change)

        mock_col_instance.cast.assert_called_once_with("decimal(38, 38)")
