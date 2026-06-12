"""Integration tests for profile-aware compare_results."""

from __future__ import annotations

import unittest

from compare import compare_results
from models import ColumnProfile, EmrTableResult, TableBaseline, TableProfile


class ProfileCompareResultsTests(unittest.TestCase):
    def _baseline(self, **kwargs) -> TableBaseline:
        defaults = {
            "dag": "dag",
            "table": "dim_x",
            "layer": "dw",
            "load_start_date": "2026-06-10",
            "load_end_date": "2026-06-11",
            "schema": [("id_user", "bigint")],
            "count": 100,
            "sample_rows": 0,
            "sample": [],
            "order_by_cols": ["id_user"],
            "time_pinned_functions": [],
            "non_comparable_cols": [],
        }
        defaults.update(kwargs)
        return TableBaseline(**defaults)

    def _emr(self, **kwargs) -> EmrTableResult:
        defaults = {
            "schema": [("id_user", "bigint")],
            "count": 100,
            "sample": [],
        }
        defaults.update(kwargs)
        return EmrTableResult(**defaults)

    def test_profile_match_passes(self) -> None:
        profile = TableProfile(
            columns={
                "id_user": ColumnProfile(
                    null_count=0,
                    checksum="abc",
                    checksum_sum="1000",
                )
            }
        )
        result = compare_results(
            self._baseline(profile=profile),
            self._emr(profile=profile),
        )
        self.assertEqual(result.status, "PASS")
        self.assertIn("profile=ok", result.message)

    def test_null_mismatch_fails(self) -> None:
        base_profile = TableProfile(
            columns={"id_user": ColumnProfile(null_count=0, checksum="x", checksum_sum="1")}
        )
        emr_profile = TableProfile(
            columns={"id_user": ColumnProfile(null_count=2, checksum="x", checksum_sum="1")}
        )
        result = compare_results(
            self._baseline(profile=base_profile),
            self._emr(profile=emr_profile),
        )
        self.assertEqual(result.status, "FAIL")
        self.assertTrue(any("Null count" in issue for issue in result.profile_issues))

    def test_skip_profile_ignores_missing_profile(self) -> None:
        result = compare_results(
            self._baseline(profile=None),
            self._emr(profile=None),
            skip_profile=True,
        )
        self.assertEqual(result.status, "PASS")
        self.assertIn("profile=skip", result.message)


if __name__ == "__main__":
    unittest.main()
