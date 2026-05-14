"""Unit tests for F2-01 basic rich metadata (ownership cascade, domain allowlist, failure_codes)."""

import unittest

from bietlejuice.governance.fairness_assessment.checks.findable.f2_01_basic_rich_metadata import (
    check_f2_01_basic_rich_metadata,
)


class TestF201BasicRichMetadata(unittest.TestCase):
    def test_passes_when_all_valid(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "For Rent",
            "Non-empty table description.",
        )
        self.assertTrue(r.passed)
        self.assertIsNone(r.reason)
        self.assertIsNone(r.detail)

    def test_ownership_cascade_owner_missing_first(self):
        r = check_f2_01_basic_rich_metadata(
            None,
            False,
            "For Rent",
            "Desc",
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
            "Has description.",
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "owner_email_invalid_format")
        self.assertEqual(r.detail, {"failure_codes": ["owner_email_invalid_format"]})

    def test_inactive_only_one_ownership_code(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            False,
            "People",
            "Has description.",
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "owner_not_active_employee")
        self.assertEqual(r.detail, {"failure_codes": ["owner_not_active_employee"]})

    def test_empty_domain_no_allowlist_check(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "",
            "Has description.",
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "domain_missing")
        self.assertEqual(r.detail, {"failure_codes": ["domain_missing"]})

    def test_whitespace_domain_treated_as_missing(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "   ",
            "Has description.",
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "domain_missing")
        self.assertEqual(r.detail, {"failure_codes": ["domain_missing"]})

    def test_non_empty_domain_not_in_allowlist(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "Rent",
            "Has description.",
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
            "x",
        )
        self.assertTrue(r.passed)

    def test_fullmatch_allows_ds_pricing(self):
        r = check_f2_01_basic_rich_metadata(
            "owner@quintoandar.com.br",
            True,
            "DS Pricing",
            "x",
        )
        self.assertTrue(r.passed)


if __name__ == "__main__":
    unittest.main()
