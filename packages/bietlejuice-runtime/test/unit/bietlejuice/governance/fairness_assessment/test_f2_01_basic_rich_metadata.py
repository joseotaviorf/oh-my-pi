"""Unit tests for F2-01 basic rich metadata (ownership cascade, domain allowlist, failure_codes)."""

import unittest

from bietlejuice.governance.fairness_assessment.checks.findable.f2_01_basic_rich_metadata import (
    check_f2_01_basic_rich_metadata,
)

_SUBSTANTIVE_TABLE_DESC = (
    "One row per rental contract with signed dates and property linkage; "
    "consumed by Rent revenue metrics."
)


class TestF201BasicRichMetadata(unittest.TestCase):
    def test_passes_when_all_valid(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "For Rent",
            _SUBSTANTIVE_TABLE_DESC,
            database_name="datalake_rent_clean",
            table_name="contracts",
        )
        self.assertTrue(r.passed)
        self.assertIsNone(r.reason)
        self.assertIsNone(r.detail)

    def test_ownership_cascade_owner_missing_first(self):
        r = check_f2_01_basic_rich_metadata(
            None,
            False,
            "For Rent",
            _SUBSTANTIVE_TABLE_DESC,
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "owner_missing")
        self.assertEqual(r.detail, {"failure_codes": ["owner_missing"]})

    def test_multiple_non_ownership_failures_ordered(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "",
            "",
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "domain_missing,table_description_missing")
        self.assertEqual(
            r.detail,
            {"failure_codes": ["domain_missing", "table_description_missing"]},
        )

    def test_inactive_plus_domain_and_description_failures(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            False,
            "Bad",
            "",
        )
        self.assertFalse(r.passed)
        self.assertEqual(
            r.reason,
            "owner_not_active_employee,domain_not_in_allowlist,table_description_missing",
        )
        self.assertEqual(
            r.detail,
            {
                "failure_codes": [
                    "owner_not_active_employee",
                    "domain_not_in_allowlist",
                    "table_description_missing",
                ]
            },
        )

    def test_ownership_cascade_invalid_email_skips_active_check(self):
        r = check_f2_01_basic_rich_metadata(
            "not-an-email",
            False,
            "People",
            _SUBSTANTIVE_TABLE_DESC,
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "owner_email_invalid_format")
        self.assertEqual(r.detail, {"failure_codes": ["owner_email_invalid_format"]})

    def test_inactive_only_one_ownership_code(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            False,
            "People",
            _SUBSTANTIVE_TABLE_DESC,
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "owner_not_active_employee")
        self.assertEqual(r.detail, {"failure_codes": ["owner_not_active_employee"]})

    def test_empty_domain_no_allowlist_check(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "",
            _SUBSTANTIVE_TABLE_DESC,
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "domain_missing")
        self.assertEqual(r.detail, {"failure_codes": ["domain_missing"]})

    def test_whitespace_domain_treated_as_missing(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "   ",
            _SUBSTANTIVE_TABLE_DESC,
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "domain_missing")
        self.assertEqual(r.detail, {"failure_codes": ["domain_missing"]})

    def test_non_empty_domain_not_in_allowlist(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "Rent",
            _SUBSTANTIVE_TABLE_DESC,
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "domain_not_in_allowlist")
        self.assertEqual(r.detail, {"failure_codes": ["domain_not_in_allowlist"]})

    def test_domain_and_description_failures_merge(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "InvalidDomain",
            "",
        )
        self.assertFalse(r.passed)
        self.assertEqual(
            r.reason,
            "domain_not_in_allowlist,table_description_missing",
        )
        self.assertEqual(
            r.detail,
            {"failure_codes": ["domain_not_in_allowlist", "table_description_missing"]},
        )

    def test_fullmatch_allows_data_platform(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "Data Platform",
            _SUBSTANTIVE_TABLE_DESC,
        )
        self.assertTrue(r.passed)

    def test_fullmatch_allows_ds_pricing(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "DS Pricing",
            _SUBSTANTIVE_TABLE_DESC,
        )
        self.assertTrue(r.passed)

    def test_table_description_not_substantive(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "For Rent",
            "tabela com informacoes de usuarios",
            database_name="datalake_x_clean",
            table_name="usuarios",
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "table_description_not_substantive")
        self.assertEqual(
            r.detail,
            {
                "failure_codes": ["table_description_not_substantive"],
                "table_description_reason_code": "boilerplate_or_name_echo",
            },
        )

    def test_short_table_description_not_substantive(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "Data Platform",
            "x",
        )
        self.assertFalse(r.passed)
        self.assertIn("table_description_not_substantive", r.reason or "")
        self.assertEqual(
            r.detail.get("table_description_reason_code"),
            "too_short",
        )


if __name__ == "__main__":
    unittest.main()
