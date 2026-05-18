"""Tests for information_schema-backed catalog resolution."""

from __future__ import annotations

import unittest
from unittest.mock import MagicMock


class TestExistsSetAndFieldMapFromCollectRows(unittest.TestCase):
    def test_lowercases_column_names(self) -> None:
        from bietlejuice.governance.fairness_assessment.adapters.columns_metastore import (
            _exists_set_and_field_map_from_collect_rows,
        )

        rows = [
            {
                "database_name": "dw_demo",
                "table_name": "fact_orders",
                "cols": {"Id_Order", "AMOUNT"},
            },
        ]
        exists, fields = _exists_set_and_field_map_from_collect_rows(rows)
        self.assertIn(("dw_demo", "fact_orders"), exists)
        self.assertEqual(
            fields[("dw_demo", "fact_orders")],
            frozenset({"id_order", "amount"}),
        )

    def test_none_cols_is_empty_frozenset(self) -> None:
        from bietlejuice.governance.fairness_assessment.adapters.columns_metastore import (
            _exists_set_and_field_map_from_collect_rows,
        )

        rows = [{"database_name": "a", "table_name": "b", "cols": None}]
        exists, fields = _exists_set_and_field_map_from_collect_rows(rows)
        self.assertEqual(fields[("a", "b")], frozenset())


class TestResolvePhysicalColumnsFromInformationSchema(unittest.TestCase):
    def test_returns_empty_when_table_read_fails(self) -> None:
        from bietlejuice.governance.fairness_assessment.adapters.columns_metastore import (
            resolve_physical_columns_from_information_schema,
        )

        spark = MagicMock()
        spark.table.side_effect = RuntimeError("no information schema")

        distinct = MagicMock()
        select_mock = MagicMock()
        select_mock.distinct.return_value = distinct
        td_df = MagicMock()
        td_df.select.return_value = select_mock

        exists, fields, tag = resolve_physical_columns_from_information_schema(
            spark, td_df
        )

        self.assertEqual(exists, set())
        self.assertEqual(fields, {})
        self.assertIsNone(tag)
