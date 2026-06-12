"""Tests for profile SQL generation and parsing."""

from __future__ import annotations

import unittest

from models import ColumnProfile, TableProfile
from profile import (
    build_profile_query,
    compare_checksums,
    compare_delta_pct,
    compare_null_counts,
    is_profileable_type,
    parse_profile_from_row,
    profile_from_dict,
    profile_to_dict,
    select_profile_columns,
)
from decimal import Decimal


class ProfileQueryTests(unittest.TestCase):
    def test_is_profileable_type_skips_complex(self) -> None:
        self.assertTrue(is_profileable_type("bigint"))
        self.assertFalse(is_profileable_type("array<string>"))
        self.assertFalse(is_profileable_type("struct<a:int>"))

    def test_build_profile_query_includes_count_null_and_checksum(self) -> None:
        schema = [("id_user", "bigint"), ("name", "string")]
        query, shell = build_profile_query("SELECT 1 AS id_user, 'a' AS name", schema)
        self.assertIn("COUNT(*) AS cnt", query)
        self.assertIn("COUNT_IF(`id_user` IS NULL) AS `null_id_user`", query)
        self.assertIn("chk_sum_id_user", query)
        self.assertIn("chk_id_user", query)
        self.assertIn("xxhash64", query)
        self.assertIn("DECIMAL(38, 0)", query)
        self.assertIn("SHA2", query)
        self.assertEqual(set(shell.columns.keys()), {"id_user", "name"})

    def test_checksum_skipped_columns_omit_checksum_exprs(self) -> None:
        schema = [("id_user", "bigint"), ("ts_load", "timestamp")]
        query, shell = build_profile_query(
            "SELECT 1 AS id_user, current_timestamp() AS ts_load",
            schema,
            checksum_skipped={"ts_load"},
        )
        self.assertIn("null_ts_load", query)
        self.assertNotIn("chk_ts_load", query)
        self.assertIn("chk_id_user", query)
        self.assertIn("ts_load", shell.checksum_skipped_columns)

    def test_select_profile_columns_truncates_wide_schema(self) -> None:
        schema = [(f"col_{idx}", "int") for idx in range(130)]
        profileable, skipped, truncated, _ = select_profile_columns(schema, max_columns=120)
        self.assertEqual(len(profileable), 120)
        self.assertEqual(len(truncated), 10)
        self.assertEqual(skipped, [])

    def test_parse_profile_from_row(self) -> None:
        _, shell = build_profile_query(
            "SELECT 1 AS id_user",
            [("id_user", "bigint")],
        )
        row = {
            "cnt": 10,
            "null_id_user": 2,
            "chk_sum_id_user": "12345",
            "chk_id_user": "abc123",
        }
        profile = parse_profile_from_row(row, shell)
        self.assertEqual(profile.columns["id_user"].null_count, 2)
        self.assertEqual(profile.columns["id_user"].checksum, "abc123")
        self.assertEqual(profile.columns["id_user"].checksum_sum, "12345")

    def test_profile_round_trip_dict(self) -> None:
        profile = TableProfile(
            columns={
                "id_user": ColumnProfile(
                    null_count=1,
                    checksum="deadbeef",
                    checksum_sum="999",
                )
            },
            checksum_skipped_columns=["ts_load"],
        )
        restored = profile_from_dict(profile_to_dict(profile))
        assert restored is not None
        self.assertEqual(restored.columns["id_user"].checksum, "deadbeef")
        self.assertEqual(restored.checksum_skipped_columns, ["ts_load"])


class ProfileCompareTests(unittest.TestCase):
    def _profile(self, **columns: tuple[int, str, str]) -> TableProfile:
        return TableProfile(
            columns={
                name: ColumnProfile(
                    null_count=null_count,
                    checksum=checksum,
                    checksum_sum=checksum_sum,
                )
                for name, (null_count, checksum, checksum_sum) in columns.items()
            }
        )

    def test_compare_null_counts_fail_on_mismatch(self) -> None:
        baseline = self._profile(id_user=(0, "a", "100"))
        emr = self._profile(id_user=(1, "a", "100"))
        ok, issues, status = compare_null_counts(baseline, emr)
        self.assertFalse(ok)
        self.assertEqual(status, "FAIL")
        self.assertTrue(issues)

    def test_compare_checksums_pass_on_exact_hex(self) -> None:
        baseline = self._profile(id_user=(0, "abc", "1000"))
        emr = self._profile(id_user=(0, "abc", "2000"))
        ok, issues, warn, status = compare_checksums(baseline, emr)
        self.assertTrue(ok)
        self.assertEqual(status, "PASS")
        self.assertFalse(issues)

    def test_compare_checksums_warn_on_small_sum_delta(self) -> None:
        baseline = self._profile(id_user=(0, "aaa", "1000000"))
        emr = self._profile(id_user=(0, "bbb", "1002000"))
        ok, issues, warn, status = compare_checksums(baseline, emr)
        self.assertFalse(ok)
        self.assertEqual(status, "WARN")
        self.assertTrue(warn)

    def test_compare_checksums_fail_on_large_sum_delta(self) -> None:
        baseline = self._profile(id_user=(0, "aaa", "1000000"))
        emr = self._profile(id_user=(0, "bbb", "2000000"))
        ok, issues, _, status = compare_checksums(baseline, emr)
        self.assertFalse(ok)
        self.assertEqual(status, "FAIL")

    def test_compare_delta_pct_bands(self) -> None:
        delta, status = compare_delta_pct(Decimal(1000), Decimal(1000))
        self.assertEqual(status, "PASS")
        delta, status = compare_delta_pct(Decimal(1000), Decimal(1002))
        self.assertEqual(status, "WARN")
        delta, status = compare_delta_pct(Decimal(1000), Decimal(1060))
        self.assertEqual(status, "FAIL")


if __name__ == "__main__":
    unittest.main()
