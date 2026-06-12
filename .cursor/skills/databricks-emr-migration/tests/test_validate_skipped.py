"""Tests for compare-mode early exit when no tables need translation."""

from __future__ import annotations

import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path
from unittest import mock

import validate as validate_module


class TestValidateFullySkipped(unittest.TestCase):
    def test_compare_mode_writes_report_when_allowlist_empty(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            import report as report_module

            original_reports_root = report_module.REPORTS_ROOT
            report_module.REPORTS_ROOT = Path(tmp) / "reports"
            try:
                args = mock.Mock(
                    domain="fintech",
                    dag="dw_credit_analysis",
                    phase="compare",
                    table=None,
                    all_tables=False,
                )
                exit_code = validate_module._finalize_compare_run(
                    args,
                    [],
                    skipped_tables=["dim_drop_reason"],
                    db_cluster_id="",
                    emr_cluster_id="",
                    load_start="2026-06-04",
                    load_end="2026-06-05",
                )
                self.assertEqual(exit_code, 0)
                reports = list(report_module.REPORTS_ROOT.rglob("*.md"))
                self.assertEqual(len(reports), 2)
                summary = report_module.REPORTS_ROOT / "fintech" / "MIGRATION_SUMMARY.md"
                self.assertTrue(summary.exists())
                self.assertIn("Skipped", summary.read_text(encoding="utf-8"))
            finally:
                report_module.REPORTS_ROOT = original_reports_root

    def test_main_compare_early_exit_writes_report_and_summary(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            import report as report_module

            original_reports_root = report_module.REPORTS_ROOT
            report_module.REPORTS_ROOT = Path(tmp) / "reports"
            argv = [
                "validate.py",
                "--dag",
                "dw_credit_analysis",
                "--domain",
                "fintech",
                "--phase",
                "compare",
                "--cluster",
                "c-test",
            ]
            try:
                with (
                    mock.patch.object(sys, "argv", argv),
                    mock.patch.object(
                        validate_module,
                        "_resolve_table_allowlist",
                        return_value=(set(), ["dim_drop_reason"]),
                    ),
                    mock.patch.object(validate_module, "validate_cli_args"),
                    mock.patch.object(validate_module, "validate_iso_date"),
                    mock.patch.object(validate_module, "validate_git_ref"),
                ):
                    exit_code = validate_module.main()

                self.assertEqual(exit_code, 0)
                dag_report = (
                    report_module.REPORTS_ROOT
                    / "fintech"
                    / f"dw_credit_analysis_{date.today()}.md"
                )
                summary = report_module.REPORTS_ROOT / "fintech" / "MIGRATION_SUMMARY.md"
                self.assertTrue(dag_report.exists(), "DAG report must be written on early exit")
                self.assertTrue(summary.exists(), "MIGRATION_SUMMARY must be updated on early exit")
                self.assertIn("Skipped", summary.read_text(encoding="utf-8"))
                self.assertIn("EMR-compatible on master", dag_report.read_text(encoding="utf-8"))
            finally:
                report_module.REPORTS_ROOT = original_reports_root


if __name__ == "__main__":
    unittest.main()
