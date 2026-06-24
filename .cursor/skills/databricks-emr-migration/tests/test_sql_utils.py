import sys
import unittest
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

from sql_utils import (
    apply_cdc_clean_injection,
    detect_non_comparable_cols,
    pin_sql,
)


class PinSqlTests(unittest.TestCase):
    def test_pins_lowercase_time_functions(self) -> None:
        sql = (
            "SELECT * FROM t "
            "WHERE dt = current_date() AND ts < current_timestamp() AND x = now()"
        )
        pinned = pin_sql(sql, "2026-06-04", "2026-06-05")
        self.assertIn("DATE '2026-06-05'", pinned)
        self.assertIn("TIMESTAMP '2026-06-04 00:00:00'", pinned)
        self.assertNotIn("current_date()", pinned.lower())
        self.assertNotIn("current_timestamp()", pinned.lower())
        self.assertNotIn("now()", pinned.lower())

    def test_pins_uppercase_time_functions(self) -> None:
        sql = "SELECT CURRENT_DATE(), NOW(), CURRENT_TIMESTAMP()"
        pinned = pin_sql(sql, "2026-06-04", "2026-06-05")
        self.assertEqual(
            pinned,
            "SELECT DATE '2026-06-05', TIMESTAMP '2026-06-04 00:00:00', "
            "TIMESTAMP '2026-06-04 00:00:00'",
        )

    def test_pins_bare_current_date(self) -> None:
        pinned = pin_sql("WHERE x = CURRENT_DATE", "2026-06-04", "2026-06-05")
        self.assertEqual(pinned, "WHERE x = DATE '2026-06-05'")

    def test_collapses_literal_braces_after_date_injection(self) -> None:
        sql = "WHERE x RLIKE '\\\\d{{1,2}}$' AND dt >= '{load_end_date}'"
        pinned = pin_sql(sql, "2026-06-04", "2026-06-05")
        self.assertIn("\\\\d{1,2}", pinned)
        self.assertNotIn("{{", pinned)
        self.assertIn("2026-06-05", pinned)


class CdcInjectionTests(unittest.TestCase):
    def test_injects_cdc_columns_before_first_from_schema_table(self) -> None:
        sql = """WITH deduped AS (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
    FROM datalake_hub_services_raw.observation
)
SELECT id, op_cdc, ts_cdc_transaction, ts_database_transaction
FROM deduped
WHERE rn = 1"""
        injected = apply_cdc_clean_injection(sql)
        self.assertIn(",op_cdc\n", injected)
        self.assertIn(",ts_cdc_transaction\n", injected)
        self.assertIn(",ts_database_transaction\n", injected)
        self.assertEqual(injected.count("op_cdc"), 2)


class DetectNonComparableColsTests(unittest.TestCase):
    def test_includes_ts_load_and_cdc_columns(self) -> None:
        cols = detect_non_comparable_cols(
            [
                "id",
                "ts_load",
                "op_cdc",
                "ts_cdc_transaction",
                "ts_database_transaction",
            ]
        )
        self.assertEqual(
            cols,
            [
                "ts_load",
                "op_cdc",
                "ts_cdc_transaction",
                "ts_database_transaction",
            ],
        )


if __name__ == "__main__":
    unittest.main()
