"""A1.2-02: an access approver is identified via the ``Approvers`` ownership type."""

import unittest

from bietlejuice.governance.fairness_assessment.checks.accessible import (
    check_a1_2_02_approver_ownership,
)


class TestA1202ApproverOwnership(unittest.TestCase):
    def test_passes_when_approver_present(self):
        result = check_a1_2_02_approver_ownership(True)
        self.assertEqual(result.requirement_id, "A1.2-02")
        self.assertTrue(result.passed)
        self.assertIsNone(result.reason)

    def test_fails_when_no_approver(self):
        result = check_a1_2_02_approver_ownership(False)
        self.assertFalse(result.passed)
        self.assertEqual(result.reason, "no_approver_owner_in_datahub")


if __name__ == "__main__":
    unittest.main()
