import unittest
from unittest.mock import patch

from manifest import ValidationJob
from models import ValidationResult
from report import print_live_summary, write_partial_report


class TestPartialReport(unittest.TestCase):
    def test_write_partial_report_includes_pending(self) -> None:
        results = [
            ValidationResult(
                table="dw/dim_x",
                baseline_count=10,
                emr_count=10,
                count_delta_pct=0.0,
                schema_match=True,
                status="PASS",
            )
        ]
        pending = [ValidationJob("fintech", "dag", "dw", "dim_y", status="running")]
        with patch("report.REPORTS_ROOT", unittest.mock.MagicMock()):
            # use real path under skill dir tmp would be better; write to reports is gitignored
            from pathlib import Path

            skill_dir = Path(__file__).resolve().parents[1]
            with patch("report.REPORTS_ROOT", skill_dir / "reports"):
                path = write_partial_report(
                    "test_domain_partial",
                    "test_dag_partial",
                    results,
                    pending_jobs=pending,
                    run_id="run1",
                    load_start_date="2026-06-04",
                    load_end_date="2026-06-05",
                )
        content = path.read_text(encoding="utf-8")
        self.assertIn("1/2 compared", content)
        self.assertIn("dim_y", content)
        self.assertIn("validation in progress", content)
        path.unlink(missing_ok=True)
        path.parent.rmdir()

    def test_print_live_summary(self) -> None:
        from manifest import RunManifest, ValidationJob

        manifest = RunManifest(
            run_id="r1",
            load_start_date="a",
            load_end_date="b",
            jobs=[
                ValidationJob("f", "d", "dw", "t1", status="compared", verdict="PASS"),
                ValidationJob("f", "d", "dw", "t2", status="running"),
            ],
        )
        with patch("builtins.print") as mock_print:
            print_live_summary(manifest)
        self.assertTrue(mock_print.called)


if __name__ == "__main__":
    import unittest.mock

    unittest.main()
