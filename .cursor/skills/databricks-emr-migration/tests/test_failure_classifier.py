"""Tests for failure_classifier."""

from __future__ import annotations

import unittest

from failure_classifier import (
    failure_retry_label,
    is_emr_syntax_failure,
    is_infra_failure,
    is_parity_failure,
)


class TestFailureClassifier(unittest.TestCase):
    def test_syntax_failures(self) -> None:
        self.assertTrue(is_emr_syntax_failure("[PARSE_SYNTAX_ERROR] near 'SELECT'"))
        self.assertTrue(is_emr_syntax_failure("org.apache.spark.sql.catalyst.parser.ParseException"))
        self.assertTrue(is_emr_syntax_failure("[UNSUPPORTED_FEATURE] QUALIFY"))
        self.assertTrue(is_emr_syntax_failure("Syntax error at or near 'FROM'"))
        self.assertTrue(is_emr_syntax_failure("missing ')' in expression"))

    def test_parity_not_syntax(self) -> None:
        self.assertFalse(is_emr_syntax_failure("count_delta=83.2% schema=ok"))
        self.assertTrue(is_parity_failure("count_delta=83.2% schema=ok"))
        self.assertTrue(is_parity_failure("schema=fail: missing column foo"))

    def test_infra_not_syntax(self) -> None:
        msg = "AccessDenied: not authorized to perform: s3:GetObject"
        self.assertTrue(is_infra_failure(msg))
        self.assertFalse(is_emr_syntax_failure(msg))
        self.assertEqual(failure_retry_label(msg), "no")

    def test_syntax_retry_label(self) -> None:
        self.assertEqual(failure_retry_label("[PARSE_SYNTAX_ERROR]"), "yes")
        self.assertEqual(failure_retry_label("count_delta=10%"), "no")


if __name__ == "__main__":
    unittest.main()
