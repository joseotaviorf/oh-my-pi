"""Tests for validation report formatting."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from report import (
    aggregate_dag_status,
    format_summary_table,
    is_fully_skipped_dag,
    print_batch_gate_summary,
    syntax_failures,
    update_migration_summary,
    verdict_label,
    write_report,
    _format_profile_section,
    _format_profile_table,
    _truncate_checksum,
)
from models import ColumnProfile, TableProfile, ValidationResult


def _result(
    table: str,
    status: str = "PASS",
    baseline_count: int = 100,
    emr_count: int = 100,
) -> ValidationResult:
    return ValidationResult(
        table=table,
        baseline_count=baseline_count,
        emr_count=emr_count,
        count_delta_pct=0.0,
        schema_match=status != "FAIL",
        schema_issues=[] if status != "FAIL" else ["Type mismatch"],
        sample_match=status == "PASS",
        sample_diff_rows=[],
        status=status,
        message="ok" if status == "PASS" else "fail",
    )


class TestReport(unittest.TestCase):
    def test_verdict_label(self) -> None:
        self.assertEqual(verdict_label("PASS"), "OK")
        self.assertEqual(verdict_label("WARN"), "WARN")
        self.assertEqual(verdict_label("MANUAL_CHECK"), "MANUAL")
        self.assertEqual(verdict_label("FAIL"), "NOT OK")

    def test_aggregate_dag_status_warn_only_allows_pr(self) -> None:
        results = [_result("a"), _result("b", "WARN")]
        passed, warned, failed, manual, pr_allowed = aggregate_dag_status(results)
        self.assertEqual((passed, warned, failed, manual, pr_allowed), (1, 1, 0, 0, True))

    def test_syntax_failures_helper(self) -> None:
        results = [
            _result("a", "FAIL"),
            ValidationResult(
                table="b",
                baseline_count=0,
                emr_count=0,
                count_delta_pct=0.0,
                schema_match=False,
                status="FAIL",
                message="[PARSE_SYNTAX_ERROR] near 'SELECT'",
            ),
        ]
        self.assertEqual(len(syntax_failures(results)), 1)
        self.assertEqual(syntax_failures(results)[0].table, "b")

    def test_write_report_excluded_section(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            import report as report_module

            original_root = report_module.REPORTS_ROOT
            report_module.REPORTS_ROOT = Path(tmp) / "reports"
            try:
                path = write_report(
                    "fintech",
                    "dw_credit_analysis",
                    [_result("broken", "FAIL")],
                )
                content = path.read_text(encoding="utf-8")
                self.assertIn("Excluded from PR", content)
                self.assertIn("PR allowed | **No**", content)
            finally:
                report_module.REPORTS_ROOT = original_root

    def test_update_migration_summary_blocked_on_fail(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            import report as report_module

            original_root = report_module.REPORTS_ROOT
            report_module.REPORTS_ROOT = Path(tmp) / "reports"
            try:
                report_path = report_module.REPORTS_ROOT / "fintech" / "dag_2026-06-05.md"
                report_path.parent.mkdir(parents=True)
                report_path.write_text("# report", encoding="utf-8")
                summary = update_migration_summary(
                    "fintech",
                    "dw_credit_analysis",
                    report_path,
                    [_result("broken", "FAIL")],
                )
                content = summary.read_text(encoding="utf-8")
                self.assertIn("Blocked", content)
            finally:
                report_module.REPORTS_ROOT = original_root

    def test_update_migration_summary_warnings_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            import report as report_module

            original_root = report_module.REPORTS_ROOT
            report_module.REPORTS_ROOT = Path(tmp) / "reports"
            try:
                report_path = report_module.REPORTS_ROOT / "fintech" / "dag_2026-06-05.md"
                report_path.parent.mkdir(parents=True)
                report_path.write_text("# report", encoding="utf-8")
                summary = update_migration_summary(
                    "fintech",
                    "dw_credit_analysis",
                    report_path,
                    [_result("a", "WARN")],
                )
                content = summary.read_text(encoding="utf-8")
                self.assertIn("Migrated (warnings)", content)
            finally:
                report_module.REPORTS_ROOT = original_root

    def test_print_batch_gate_summary(self) -> None:
        import io
        import contextlib

        dag_results = {
            "fintech/enrich_billing": [_result("a"), _result("b", "WARN")],
            "fintech/enrich_bank": [
                _result("c"),
                ValidationResult(
                    table="quintocred_cashin",
                    baseline_count=736,
                    emr_count=4315,
                    count_delta_pct=83.2,
                    schema_match=True,
                    status="FAIL",
                    message="count_delta=83.2% schema=ok",
                ),
            ],
        }
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            print_batch_gate_summary(dag_results)
        output = buffer.getvalue()
        self.assertIn("PR eligible", output)
        self.assertIn("fintech/enrich_billing", output)
        self.assertIn("Blocked (FAIL — excluded from PR)", output)
        self.assertIn("quintocred_cashin", output)
        self.assertIn("Retry?", output)

    def test_aggregate_dag_status(self) -> None:
        results = [_result("a"), _result("b", "WARN"), _result("c", "FAIL")]
        passed, warned, failed, manual, pr_allowed = aggregate_dag_status(results)
        self.assertEqual((passed, warned, failed, manual, pr_allowed), (1, 1, 1, 0, False))

    def test_aggregate_dag_status_manual_check_blocks_pr(self) -> None:
        results = [_result("a"), _result("b", "MANUAL_CHECK")]
        passed, warned, failed, manual, pr_allowed = aggregate_dag_status(results)
        self.assertEqual((passed, warned, failed, manual, pr_allowed), (1, 0, 0, 1, False))

    def test_aggregate_dag_status_fully_skipped(self) -> None:
        passed, warned, failed, manual, pr_allowed = aggregate_dag_status(
            [],
            fully_skipped=True,
        )
        self.assertEqual((passed, warned, failed, manual, pr_allowed), (0, 0, 0, 0, False))

    def test_is_fully_skipped_dag(self) -> None:
        self.assertTrue(is_fully_skipped_dag([], ["dim_a"]))
        self.assertFalse(is_fully_skipped_dag([_result("dim_a")], ["dim_b"]))
        self.assertFalse(is_fully_skipped_dag([], []))

    def test_format_summary_table_contains_tables(self) -> None:
        table = format_summary_table([_result("dim_drop_reason")])
        self.assertIn("dim_drop_reason", table)
        self.assertIn("OK", table)

    def test_write_report_creates_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            import report as report_module

            original_root = report_module.REPORTS_ROOT
            report_module.REPORTS_ROOT = Path(tmp) / "reports"
            try:
                path = write_report(
                    "fintech",
                    "dw_credit_analysis",
                    [_result("dim_drop_reason")],
                    databricks_cluster_id="db-1",
                    emr_cluster_id="j-1",
                    load_start_date="2026-06-04",
                    load_end_date="2026-06-05",
                )
                self.assertTrue(path.exists())
                content = path.read_text(encoding="utf-8")
                self.assertIn("dim_drop_reason", content)
                self.assertIn("PR allowed", content)
            finally:
                report_module.REPORTS_ROOT = original_root

    def test_write_report_fully_skipped(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            import report as report_module

            original_root = report_module.REPORTS_ROOT
            report_module.REPORTS_ROOT = Path(tmp) / "reports"
            try:
                path = write_report(
                    "fintech",
                    "dw_credit_analysis",
                    [],
                    load_start_date="2026-06-04",
                    load_end_date="2026-06-05",
                    skipped_tables=["dim_drop_reason", "fact_events"],
                )
                content = path.read_text(encoding="utf-8")
                self.assertIn("Skipped", content)
                self.assertIn("dim_drop_reason", content)
                self.assertIn("PR allowed | **No**", content)
            finally:
                report_module.REPORTS_ROOT = original_root

    def test_update_migration_summary_appends_row(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            import report as report_module

            original_root = report_module.REPORTS_ROOT
            report_module.REPORTS_ROOT = Path(tmp) / "reports"
            try:
                report_path = report_module.REPORTS_ROOT / "fintech" / "dag_2026-06-05.md"
                report_path.parent.mkdir(parents=True)
                report_path.write_text("# report", encoding="utf-8")
                summary = update_migration_summary(
                    "fintech",
                    "dw_credit_analysis",
                    report_path,
                    [_result("dim_drop_reason")],
                )
                content = summary.read_text(encoding="utf-8")
                self.assertIn("dw_credit_analysis", content)
                self.assertIn("Migrated", content)
            finally:
                report_module.REPORTS_ROOT = original_root

    def test_update_migration_summary_skipped_status(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            import report as report_module

            original_root = report_module.REPORTS_ROOT
            report_module.REPORTS_ROOT = Path(tmp) / "reports"
            try:
                report_path = report_module.REPORTS_ROOT / "fintech" / "dag_2026-06-05.md"
                report_path.parent.mkdir(parents=True)
                report_path.write_text("# report", encoding="utf-8")
                summary = update_migration_summary(
                    "fintech",
                    "dw_credit_analysis",
                    report_path,
                    [],
                    skipped_tables=["dim_drop_reason"],
                )
                content = summary.read_text(encoding="utf-8")
                self.assertIn("Skipped", content)
                self.assertNotIn("Migrated", content)
            finally:
                report_module.REPORTS_ROOT = original_root


class TestReportProfile(unittest.TestCase):
    def test_truncate_checksum(self) -> None:
        self.assertEqual(_truncate_checksum("abcdef1234567890"), "abcdef12")
        self.assertEqual(_truncate_checksum(None), "—")
        self.assertEqual(_truncate_checksum(""), "—")

    def test_format_profile_table_matching_and_mismatch(self) -> None:
        baseline = TableProfile(
            columns={
                "id_user": ColumnProfile(null_count=0, checksum="aabbccdd11223344", checksum_sum="100"),
                "amount": ColumnProfile(null_count=2, checksum="1122334455667788", checksum_sum="200"),
                "ts_load": ColumnProfile(null_count=0),
            },
            checksum_skipped_columns=["ts_load"],
        )
        emr = TableProfile(
            columns={
                "id_user": ColumnProfile(null_count=0, checksum="aabbccdd11223344", checksum_sum="100"),
                "amount": ColumnProfile(null_count=5, checksum="1122334455667788", checksum_sum="200"),
                "ts_load": ColumnProfile(null_count=0),
            },
            checksum_skipped_columns=["ts_load"],
        )
        table = _format_profile_table(baseline, emr)
        self.assertIn("`id_user`", table)
        self.assertIn("aabbccdd", table)
        self.assertIn("| ok |", table)
        self.assertIn("| fail |", table)
        self.assertIn("n/a", table)

    def test_write_report_includes_profile_section(self) -> None:
        baseline = TableProfile(
            columns={
                "sk_house": ColumnProfile(null_count=0, checksum="deadbeef01234567", checksum_sum="42"),
            }
        )
        emr = TableProfile(
            columns={
                "sk_house": ColumnProfile(null_count=0, checksum="deadbeef01234567", checksum_sum="42"),
            }
        )
        result = ValidationResult(
            table="dw/fact_house_listings",
            baseline_count=100,
            emr_count=100,
            count_delta_pct=0.0,
            schema_match=True,
            status="PASS",
            message="schema=ok, count_delta=0.000%, profile=ok, sample=skipped",
            baseline_profile=baseline,
            emr_profile=emr,
        )
        with tempfile.TemporaryDirectory() as tmp:
            import report as report_module

            original_root = report_module.REPORTS_ROOT
            report_module.REPORTS_ROOT = Path(tmp) / "reports"
            try:
                path = write_report(
                    "house_and_listing",
                    "dw_listing",
                    [result],
                )
                content = path.read_text(encoding="utf-8")
                self.assertIn("## Column profile", content)
                self.assertIn("### dw/fact_house_listings", content)
                self.assertIn("| DB null | EMR null | DB chk | EMR chk | Match |", content)
                self.assertIn("`sk_house`", content)
                self.assertIn("deadbeef", content)
            finally:
                report_module.REPORTS_ROOT = original_root

    def test_format_profile_section_skips_when_profile_missing(self) -> None:
        result = _result("dw/dim_condo")
        self.assertEqual(_format_profile_section([result]), "")


if __name__ == "__main__":
    unittest.main()
