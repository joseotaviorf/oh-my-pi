"""Tests for compare-mode error handling and mandatory reporting."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

import validate as validate_module


class TestValidateCompareErrors(unittest.TestCase):
    def test_compare_mode_writes_report_when_phase2_fails(self) -> None:
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
                "--sync",
                "--cluster",
                "c-test",
            ]
            try:
                with (
                    mock.patch.object(sys, "argv", argv),
                    mock.patch.object(
                        validate_module,
                        "_resolve_table_allowlist",
                        return_value=({("dw", "dim_drop_reason")}, []),
                    ),
                    mock.patch.object(validate_module, "validate_cli_args"),
                    mock.patch.object(validate_module, "validate_iso_date"),
                    mock.patch.object(validate_module, "validate_git_ref"),
                    mock.patch.object(
                        validate_module,
                        "tables_needing_baseline",
                        return_value=[("dim_drop_reason", "dw")],
                    ),
                    mock.patch.object(
                        validate_module,
                        "_run_phase2",
                        side_effect=RuntimeError("Databricks baseline capture failed"),
                    ),
                ):
                    exit_code = validate_module.main()

                self.assertEqual(exit_code, 1)
                reports = list(report_module.REPORTS_ROOT.rglob("*.md"))
                self.assertGreaterEqual(len(reports), 2)
                dag_report = next(
                    path
                    for path in reports
                    if path.name.startswith("dw_credit_analysis_")
                )
                self.assertIn("Databricks baseline capture failed", dag_report.read_text())
            finally:
                report_module.REPORTS_ROOT = original_reports_root

    def test_compare_mode_writes_report_when_dag_path_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            import report as report_module

            original_reports_root = report_module.REPORTS_ROOT
            report_module.REPORTS_ROOT = Path(tmp) / "reports"
            argv = [
                "validate.py",
                "--dag",
                "no_such_dag",
                "--domain",
                "no_such_domain",
                "--phase",
                "compare",
                "--sync",
                "--cluster",
                "c-test",
            ]
            try:
                with (
                    mock.patch.object(sys, "argv", argv),
                    mock.patch.object(validate_module, "validate_cli_args"),
                    mock.patch.object(validate_module, "validate_iso_date"),
                    mock.patch.object(validate_module, "validate_git_ref"),
                ):
                    exit_code = validate_module.main()

                self.assertEqual(exit_code, 1)
                reports = list(report_module.REPORTS_ROOT.rglob("*.md"))
                self.assertGreaterEqual(len(reports), 2)
                dag_report = next(
                    path for path in reports if path.name.startswith("no_such_dag_")
                )
                self.assertIn("DAG path not found", dag_report.read_text())
            finally:
                report_module.REPORTS_ROOT = original_reports_root

    def test_compare_mode_continues_emr_when_one_baseline_capture_fails(self) -> None:
        argv = [
            "validate.py",
            "--dag",
            "dw_credit_analysis",
            "--domain",
            "fintech",
            "--phase",
            "compare",
            "--sync",
            "--cluster",
            "c-test",
        ]
        ok_result = validate_module.ValidationResult(
            table="dw/dim_other",
            baseline_count=10,
            emr_count=10,
            count_delta_pct=0.0,
            schema_match=True,
            status="PASS",
            message="ok",
        )
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(
                validate_module,
                "_resolve_table_allowlist",
                return_value=(
                    {("dw", "dim_drop_reason"), ("dw", "dim_other")},
                    [],
                ),
            ),
            mock.patch.object(validate_module, "validate_cli_args"),
            mock.patch.object(validate_module, "validate_iso_date"),
            mock.patch.object(validate_module, "validate_git_ref"),
            mock.patch.object(
                validate_module,
                "tables_needing_baseline",
                return_value=[
                    ("dim_drop_reason", "dw"),
                    ("dim_other", "dw"),
                ],
            ),
            mock.patch.object(
                validate_module,
                "_run_phase2",
                side_effect=[
                    RuntimeError("Databricks baseline capture failed for dw/dim_drop_reason"),
                    ([mock.Mock()], "db-123"),
                ],
            ),
            mock.patch.object(
                validate_module,
                "load_baselines",
                return_value=[mock.Mock()],
            ),
            mock.patch.object(
                validate_module,
                "_run_phase4",
                return_value=(True, "j-EMR123", [ok_result]),
            ) as run_phase4,
            mock.patch.object(validate_module, "_finalize_compare_run", return_value=1) as finalize,
        ):
            validate_module.main()

        results = finalize.call_args.args[1]
        self.assertEqual(len(results), 2)
        failed = next(result for result in results if result.status == "FAIL")
        passed = next(result for result in results if result.status == "PASS")
        self.assertEqual(failed.table, "dw/dim_drop_reason")
        self.assertEqual(passed.table, "dw/dim_other")
        run_phase4.assert_called_once()

    def test_compare_mode_preserves_baseline_failures_when_phase4_skipped(self) -> None:
        """Baseline capture failures must survive when Phase 4 never runs."""
        argv = [
            "validate.py",
            "--dag",
            "dw_credit_analysis",
            "--domain",
            "fintech",
            "--phase",
            "compare",
            "--sync",
            "--cluster",
            "c-test",
        ]
        baseline_error = "Databricks baseline capture failed for dw/dim_drop_reason"
        load_error = "Baseline directory not found: /tmp/missing"
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(
                validate_module,
                "_resolve_table_allowlist",
                return_value=(
                    {("dw", "dim_drop_reason"), ("dw", "dim_credit_analysis")},
                    [],
                ),
            ),
            mock.patch.object(validate_module, "validate_cli_args"),
            mock.patch.object(validate_module, "validate_iso_date"),
            mock.patch.object(validate_module, "validate_git_ref"),
            mock.patch.object(
                validate_module,
                "tables_needing_baseline",
                return_value=[
                    ("dim_drop_reason", "dw"),
                    ("dim_credit_analysis", "dw"),
                ],
            ),
            mock.patch.object(
                validate_module,
                "_run_phase2",
                side_effect=[
                    RuntimeError(baseline_error),
                    ([mock.Mock()], "db-123"),
                ],
            ),
            mock.patch.object(
                validate_module,
                "load_baselines",
                side_effect=FileNotFoundError(load_error),
            ),
            mock.patch.object(
                validate_module,
                "_run_phase4",
            ) as run_phase4,
            mock.patch.object(validate_module, "_finalize_compare_run", return_value=1) as finalize,
        ):
            validate_module.main()

        run_phase4.assert_not_called()
        results = finalize.call_args.args[1]
        self.assertEqual(len(results), 2)

        failed_baseline = next(
            result for result in results if result.table == "dw/dim_drop_reason"
        )
        failed_workflow = next(
            result for result in results if result.table == "dw/dim_credit_analysis"
        )
        self.assertEqual(failed_baseline.message, baseline_error)
        self.assertEqual(failed_workflow.message, load_error)

    def test_compare_mode_preserves_baseline_failures_when_emr_resolution_fails(
        self,
    ) -> None:
        argv = [
            "validate.py",
            "--dag",
            "dw_credit_analysis",
            "--domain",
            "fintech",
            "--phase",
            "compare",
            "--sync",
            "--cluster",
            "c-test",
        ]
        baseline_error = "Databricks baseline capture failed for dw/dim_drop_reason"
        emr_error = "No migration-validation EMR cluster available"
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(
                validate_module,
                "_resolve_table_allowlist",
                return_value=(
                    {("dw", "dim_drop_reason"), ("dw", "dim_credit_analysis")},
                    [],
                ),
            ),
            mock.patch.object(validate_module, "validate_cli_args"),
            mock.patch.object(validate_module, "validate_iso_date"),
            mock.patch.object(validate_module, "validate_git_ref"),
            mock.patch.object(
                validate_module,
                "tables_needing_baseline",
                return_value=[("dim_drop_reason", "dw")],
            ),
            mock.patch.object(
                validate_module,
                "_run_phase2",
                side_effect=RuntimeError(baseline_error),
            ),
            mock.patch.object(
                validate_module,
                "load_baselines",
                return_value=[mock.Mock()],
            ),
            mock.patch.object(
                validate_module,
                "_run_phase4",
                side_effect=RuntimeError(emr_error),
            ),
            mock.patch.object(validate_module, "_finalize_compare_run", return_value=1) as finalize,
        ):
            validate_module.main()

        results = finalize.call_args.args[1]
        self.assertEqual(len(results), 2)

        failed_baseline = next(
            result for result in results if result.table == "dw/dim_drop_reason"
        )
        failed_emr = next(
            result for result in results if result.table == "dw/dim_credit_analysis"
        )
        self.assertEqual(failed_baseline.message, baseline_error)
        self.assertEqual(failed_emr.message, emr_error)

    def test_phase4_exits_nonzero_when_emr_validation_fails(self) -> None:
        argv = [
            "validate.py",
            "--dag",
            "dw_credit_analysis",
            "--domain",
            "fintech",
            "--phase",
            "4",
            "--cluster",
            "c-test",
        ]
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(
                validate_module,
                "_resolve_table_allowlist",
                return_value=(None, []),
            ),
            mock.patch.object(validate_module, "validate_cli_args"),
            mock.patch.object(validate_module, "validate_iso_date"),
            mock.patch.object(validate_module, "validate_git_ref"),
            mock.patch.object(
                validate_module,
                "load_baselines",
                return_value=[mock.Mock()],
            ),
            mock.patch.object(
                validate_module,
                "_run_phase4",
                return_value=(False, "j-EMR123", []),
            ),
        ):
            exit_code = validate_module.main()

        self.assertEqual(exit_code, 1)


if __name__ == "__main__":
    unittest.main()
