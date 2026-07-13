"""A1.2-01: access request path documented via the ``How to request access`` structured property."""

import unittest

from bietlejuice.governance.fairness_assessment.checks.accessible import (
    check_a1_2_01_access_request_documented,
)


class TestA1201AccessRequestDocumented(unittest.TestCase):
    def test_passes_when_present(self):
        result = check_a1_2_01_access_request_documented(True)
        self.assertEqual(result.requirement_id, "A1.2-01")
        self.assertTrue(result.passed)
        self.assertIsNone(result.reason)

    def test_fails_when_absent(self):
        result = check_a1_2_01_access_request_documented(False)
        self.assertFalse(result.passed)
        self.assertEqual(result.reason, "no_how_to_request_access_structured_property")


if __name__ == "__main__":
    unittest.main()
