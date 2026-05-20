"""Unit tests for FAIR assessment identifier regex and F1-03 shape validation."""

import unittest

from bietlejuice.governance.fairness_assessment.checks.findable.f1_03_addressable_fqn import (
    check_f1_03_addressable_fqn,
)
from bietlejuice.governance.fairness_assessment.checks.patterns import IDENTIFIER_RE


class TestIdentifierRe(unittest.TestCase):
    def test_accepts_amplitude_style_table_names(self):
        for name in (
            "170135_in_app_survey_answered_events",
            "155697_refer_lead_referred_events",
            "170135_in_app_survey_completed_events",
        ):
            with self.subTest(name=name):
                self.assertIsNotNone(IDENTIFIER_RE.match(name))

    def test_accepts_standard_identifiers(self):
        for name in (
            "datalake_amplitude_clean",
            "fact_contract",
            "3p_partners_performance_targets",
        ):
            with self.subTest(name=name):
                self.assertIsNotNone(IDENTIFIER_RE.match(name))

    def test_rejects_invalid_shapes(self):
        for name in ("", "170135-in-app", "170135.in_app", " 170135_x"):
            with self.subTest(name=name):
                self.assertIsNone(IDENTIFIER_RE.match(name))


class TestF103AmplitudeIdentifiers(unittest.TestCase):
    _db = "datalake_amplitude_clean"
    _tbl = "170135_in_app_survey_answered_events"

    def test_passes_shape_with_catalog_hit(self):
        r = check_f1_03_addressable_fqn(
            self._db,
            self._tbl,
            spark_catalog_hit=True,
        )
        self.assertTrue(r.passed)
        self.assertIsNone(r.reason)

    def test_catalog_miss_not_invalid_identifier(self):
        r = check_f1_03_addressable_fqn(
            self._db,
            self._tbl,
            spark_catalog_hit=False,
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "fqn_not_in_columns_metastore_snapshot")

    def test_hyphenated_table_still_invalid_identifier(self):
        r = check_f1_03_addressable_fqn(
            self._db,
            "170135-in-app-survey",
            spark_catalog_hit=True,
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "invalid_identifier_format")
