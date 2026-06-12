import sys
import unittest
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

from sql_utils import pin_sql


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


if __name__ == "__main__":
    unittest.main()
