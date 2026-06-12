import sys
import unittest
from pathlib import Path
from unittest.mock import patch

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

from baseline import (
    baseline_matches_sql,
    baseline_matches_window,
    is_baseline_fresh,
    preflight_baselines,
    resolve_pin_dates,
    tables_needing_baseline,
)
from models import TableBaseline
from sql_utils import sql_hash


def _baseline(**overrides) -> TableBaseline:
    defaults = {
        "dag": "enrich_intune",
        "table": "managed_devices",
        "layer": "enrich",
        "load_start_date": "2026-06-04",
        "load_end_date": "2026-06-05",
        "schema": [("id_device", "string")],
        "count": 10,
        "sample_rows": 1,
        "sample": [{"id_device": "1"}],
        "order_by_cols": ["id_device"],
        "time_pinned_functions": [],
        "non_comparable_cols": [],
    }
    defaults.update(overrides)
    return TableBaseline(**defaults)


class BaselineWindowTests(unittest.TestCase):
    def test_baseline_matches_window_requires_end_date(self) -> None:
        baseline = _baseline(load_end_date="")
        self.assertFalse(
            baseline_matches_window(baseline, "2026-06-04", "2026-06-05")
        )

    def test_is_baseline_fresh_rejects_stale_window(self) -> None:
        baseline = _baseline(load_start_date="2026-06-03", load_end_date="2026-06-04")
        self.assertFalse(
            is_baseline_fresh(
                baseline,
                "2026-06-04",
                "2026-06-05",
                domain="tech_platform",
            )
        )

    @patch("baseline.load_pinned_sql")
    def test_is_baseline_fresh_rejects_sql_hash_mismatch(
        self,
        mock_load_pinned_sql: unittest.mock.Mock,
    ) -> None:
        mock_load_pinned_sql.return_value = "SELECT 2"
        baseline = _baseline(sql_hash=sql_hash("SELECT 1"))
        self.assertFalse(
            is_baseline_fresh(
                baseline,
                "2026-06-04",
                "2026-06-05",
                domain="tech_platform",
                git_ref="master",
            )
        )

    @patch("baseline.load_pinned_sql")
    def test_is_baseline_fresh_accepts_matching_sql_hash(
        self,
        mock_load_pinned_sql: unittest.mock.Mock,
    ) -> None:
        pinned_sql = "SELECT 1"
        mock_load_pinned_sql.return_value = pinned_sql
        baseline = _baseline(sql_hash=sql_hash(pinned_sql))
        self.assertTrue(
            is_baseline_fresh(
                baseline,
                "2026-06-04",
                "2026-06-05",
                domain="tech_platform",
                git_ref="master",
            )
        )

    def test_is_baseline_fresh_rejects_missing_sql_hash(self) -> None:
        baseline = _baseline(sql_hash="")
        self.assertFalse(
            is_baseline_fresh(
                baseline,
                "2026-06-04",
                "2026-06-05",
                domain="tech_platform",
            )
        )

    @patch("baseline.load_pinned_sql")
    def test_baseline_matches_sql_compares_pinned_master_sql(
        self,
        mock_load_pinned_sql: unittest.mock.Mock,
    ) -> None:
        pinned_sql = "SELECT id_device FROM t WHERE dt = DATE '2026-06-04'"
        mock_load_pinned_sql.return_value = pinned_sql
        baseline = _baseline(sql_hash=sql_hash(pinned_sql))
        self.assertTrue(
            baseline_matches_sql(
                baseline,
                "tech_platform",
                "2026-06-04",
                "2026-06-05",
                git_ref="master",
            )
        )

    def test_resolve_pin_dates_uses_baseline_end_when_cli_end_empty(self) -> None:
        baseline = _baseline()
        start, end = resolve_pin_dates(baseline, "2026-06-04", "")
        self.assertEqual(start, "2026-06-04")
        self.assertEqual(end, "2026-06-05")

    def test_resolve_pin_dates_rejects_mismatched_cli_window(self) -> None:
        baseline = _baseline()
        with self.assertRaises(ValueError):
            resolve_pin_dates(baseline, "2026-06-05", "2026-06-06")

    def test_resolve_pin_dates_rejects_legacy_baseline_without_end_date(self) -> None:
        baseline = _baseline(load_end_date="")
        with self.assertRaises(ValueError):
            resolve_pin_dates(baseline, "", "")

    @patch("baseline.discover_tables")
    @patch("baseline.load_baseline_for_table")
    def test_preflight_baselines_marks_stale_window_as_missing(
        self,
        mock_load: unittest.mock.Mock,
        mock_discover: unittest.mock.Mock,
    ) -> None:
        mock_discover.return_value = [("managed_devices", "enrich")]
        mock_load.return_value = _baseline(
            load_start_date="2026-06-03",
            load_end_date="2026-06-04",
        )
        baselines, missing = preflight_baselines(
            "tech_platform",
            "enrich_intune",
            "2026-06-04",
            "2026-06-05",
        )
        self.assertEqual(baselines, [])
        self.assertEqual(missing, ["enrich/managed_devices"])

    @patch("baseline.discover_tables")
    @patch("baseline.load_baseline_for_table")
    def test_tables_needing_baseline_includes_stale_window(
        self,
        mock_load: unittest.mock.Mock,
        mock_discover: unittest.mock.Mock,
    ) -> None:
        mock_discover.return_value = [("managed_devices", "enrich")]
        mock_load.return_value = _baseline(
            load_start_date="2026-06-03",
            load_end_date="2026-06-04",
        )
        needing = tables_needing_baseline(
            "tech_platform",
            "enrich_intune",
            "2026-06-04",
            "2026-06-05",
        )
        self.assertEqual(needing, [("managed_devices", "enrich")])

    @patch("baseline.load_pinned_sql")
    @patch("baseline.discover_tables")
    @patch("baseline.load_baseline_for_table")
    def test_tables_needing_baseline_includes_sql_hash_mismatch(
        self,
        mock_load: unittest.mock.Mock,
        mock_discover: unittest.mock.Mock,
        mock_load_pinned_sql: unittest.mock.Mock,
    ) -> None:
        mock_discover.return_value = [("managed_devices", "enrich")]
        mock_load_pinned_sql.return_value = "SELECT 2"
        mock_load.return_value = _baseline(sql_hash=sql_hash("SELECT 1"))
        needing = tables_needing_baseline(
            "tech_platform",
            "enrich_intune",
            "2026-06-04",
            "2026-06-05",
            git_ref="master",
        )
        self.assertEqual(needing, [("managed_devices", "enrich")])

    @patch("baseline.load_pinned_sql")
    @patch("baseline.discover_tables")
    @patch("baseline.load_baseline_for_table")
    def test_tables_needing_baseline_treats_git_load_failure_as_stale(
        self,
        mock_load: unittest.mock.Mock,
        mock_discover: unittest.mock.Mock,
        mock_load_pinned_sql: unittest.mock.Mock,
    ) -> None:
        mock_discover.return_value = [("managed_devices", "enrich")]
        mock_load_pinned_sql.side_effect = RuntimeError("git show failed")
        mock_load.return_value = _baseline(sql_hash=sql_hash("SELECT 1"))
        needing = tables_needing_baseline(
            "tech_platform",
            "enrich_intune",
            "2026-06-04",
            "2026-06-05",
            git_ref="master",
        )
        self.assertEqual(needing, [("managed_devices", "enrich")])


if __name__ == "__main__":
    unittest.main()
