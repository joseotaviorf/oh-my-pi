"""Tests for sample column labels in validation reports."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

from models import ValidationResult
from report import format_markdown_table, format_summary_table, sample_label


class TestReportSampleLabel(unittest.TestCase):
    def test_sample_label_warn_for_minor_float_drift(self) -> None:
        result = ValidationResult(
            table="fact_amounts",
            baseline_count=1,
            emr_count=1,
            count_delta_pct=0.0,
            schema_match=True,
            sample_match=False,
            sample_warn=True,
            status="WARN",
            message="schema=ok, count_delta=0.000%, sample=warn",
        )
        self.assertEqual(sample_label(result), "warn")
        self.assertIn(" warn ", format_summary_table([result]))
        self.assertIn("| warn |", format_markdown_table([result]))


if __name__ == "__main__":
    unittest.main()
