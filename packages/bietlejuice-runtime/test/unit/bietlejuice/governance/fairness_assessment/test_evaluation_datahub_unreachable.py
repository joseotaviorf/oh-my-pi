"""Override of DataHub-dependent reasons when F4-01 reports network failure."""

import unittest

from bietlejuice.governance.fairness_assessment.checks.evaluation import (
    evaluate_mvp_checks_from_row,
)
from bietlejuice.governance.fairness_assessment.constants import (
    DATAHUB_FETCH_ERROR,
    DATAHUB_HTTP_ERROR,
    DATAHUB_UNREACHABLE_REASON,
)


def _row(**overrides):
    base = {
        "database_name": "dw_inspections",
        "table_name": "dim_contestation",
        "owner": "data.owner@quintoandar.com.br",
        "owner_email_normalized": "data.owner@quintoandar.com.br",
        "is_active_employee": True,
        "fqn_occurrence_count": 1,
        "domain": "Data Ops & Governance",
        "table_description": (
            "Dimension of contestation records with status and resolution timestamps; "
            "used by Support and Services reporting."
        ),
        "spark_table_exists": True,
        "spark_catalog_probe_status": "OK",
        "f4_01_pass": False,
        "f4_01_failure_reason": None,
        "has_data_contract": False,
        "f2_02_pass": True,
        "f2_02_failure_reason": None,
        "i1_01_pass": True,
        "i1_01_failure_reason": None,
        "i3_01_pass": False,
        "i3_02_pass": False,
        "a1_2_01_pass": False,
        "a1_2_02_pass": False,
    }
    base.update(overrides)
    return base


class TestEvaluatorDataHubUnreachableOverride(unittest.TestCase):
    def test_http_error_overrides_dependent_reasons(self):
        out = evaluate_mvp_checks_from_row(
            _row(f4_01_failure_reason=DATAHUB_HTTP_ERROR)
        )

        for rid in ("I1-02", "I3-01", "I3-02", "A1.2-01", "A1.2-02", "A1.2-03"):
            with self.subTest(requirement_id=rid):
                self.assertFalse(out[rid].passed)
                self.assertEqual(out[rid].reason, DATAHUB_UNREACHABLE_REASON)

        # F4-01 keeps the network-level reason (granularity preserved on the source check).
        self.assertEqual(out["F4-01"].reason, DATAHUB_HTTP_ERROR)

    def test_fetch_error_overrides_dependent_reasons(self):
        out = evaluate_mvp_checks_from_row(
            _row(f4_01_failure_reason=DATAHUB_FETCH_ERROR)
        )

        for rid in ("I1-02", "I3-01", "I3-02", "A1.2-01", "A1.2-02", "A1.2-03"):
            with self.subTest(requirement_id=rid):
                self.assertEqual(out[rid].reason, DATAHUB_UNREACHABLE_REASON)
        self.assertEqual(out["F4-01"].reason, DATAHUB_FETCH_ERROR)

    def test_no_override_when_f4_passes(self):
        out = evaluate_mvp_checks_from_row(
            _row(f4_01_pass=True, f4_01_failure_reason=None)
        )

        for rid in ("I1-02", "I3-01", "I3-02", "A1.2-01", "A1.2-02", "A1.2-03"):
            with self.subTest(requirement_id=rid):
                self.assertNotEqual(out[rid].reason, DATAHUB_UNREACHABLE_REASON)
        self.assertTrue(out["F4-01"].passed)

    def test_no_override_when_failure_reason_is_content_based(self):
        out = evaluate_mvp_checks_from_row(
            _row(f4_01_failure_reason="ENTITY_NOT_FOUND")
        )

        for rid in ("I1-02", "I3-01", "I3-02", "A1.2-01", "A1.2-02", "A1.2-03"):
            with self.subTest(requirement_id=rid):
                self.assertNotEqual(out[rid].reason, DATAHUB_UNREACHABLE_REASON)

    def test_passed_dependent_check_is_not_overridden(self):
        # I3-01 passes for this FQN — even if DataHub is unreachable for F4-01, a previously-passed
        # check must not be downgraded.
        out = evaluate_mvp_checks_from_row(
            _row(
                f4_01_failure_reason=DATAHUB_HTTP_ERROR,
                i3_01_pass=True,
            )
        )
        self.assertTrue(out["I3-01"].passed)
        self.assertIsNone(out["I3-01"].reason)
        # The other dependent checks still get the override.
        self.assertEqual(out["I1-02"].reason, DATAHUB_UNREACHABLE_REASON)
        self.assertEqual(out["I3-02"].reason, DATAHUB_UNREACHABLE_REASON)
        self.assertEqual(out["A1.2-03"].reason, DATAHUB_UNREACHABLE_REASON)


if __name__ == "__main__":
    unittest.main()
