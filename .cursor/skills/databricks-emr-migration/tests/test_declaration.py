import sys
import unittest
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

from declaration import resolve_order_by_cols
from query_builders import build_sample_query


class ResolveOrderByColsTests(unittest.TestCase):
    def test_fallback_uses_only_existing_column_ordinals(self) -> None:
        one_col = resolve_order_by_cols(
            "dim_x",
            [("amount", "double")],
            "fintech",
            "dw_x",
        )
        self.assertEqual(one_col, ["1"])

        two_cols = resolve_order_by_cols(
            "dim_x",
            [("amount", "double"), ("qty", "int")],
            "fintech",
            "dw_x",
        )
        self.assertEqual(two_cols, ["1", "2"])

        three_cols = resolve_order_by_cols(
            "dim_x",
            [("a", "int"), ("b", "int"), ("c", "int"), ("d", "int")],
            "fintech",
            "dw_x",
        )
        self.assertEqual(three_cols, ["1", "2", "3"])

    def test_single_column_sample_query_is_valid(self) -> None:
        order_cols = resolve_order_by_cols(
            "dim_x",
            [("amount", "double")],
            "fintech",
            "dw_x",
        )
        sample_sql = build_sample_query("SELECT amount FROM t", order_cols, 10)
        self.assertEqual(
            sample_sql,
            "SELECT * FROM (SELECT amount FROM t) AS t ORDER BY 1 LIMIT 10",
        )


if __name__ == "__main__":
    unittest.main()
