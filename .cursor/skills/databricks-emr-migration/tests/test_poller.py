import unittest
from unittest.mock import MagicMock, patch

from manifest import RunManifest, ValidationJob
from models import TableBaseline
from poller import WatchConfig, _compare_job, _job_timed_out, run_watch


class TestPoller(unittest.TestCase):
    def test_job_timed_out(self) -> None:
        job = ValidationJob(
            "fintech",
            "dag",
            "dw",
            "t",
            status="running",
            submitted_at="2000-01-01T00:00:00+00:00",
        )
        self.assertTrue(_job_timed_out(job, 60))

    def test_compare_job_missing_baseline(self) -> None:
        job = ValidationJob(
            "fintech",
            "dag",
            "dw",
            "t",
            baseline_s3_uri="s3://b/k.baseline.json",
            emr_s3_uri="s3://b/k.emr.json",
        )
        stager = MagicMock()
        with patch("poller._load_baseline_from_s3", return_value=None):
            with patch("poller._load_emr_from_s3", return_value=None):
                result = _compare_job(
                    job,
                    stager,
                    emr_env="prod",
                    skip_sample=True,
                    skip_profile=False,
                )
        self.assertEqual(result.status, "FAIL")

    def test_run_watch_completes_when_jobs_terminal(self) -> None:
        manifest = RunManifest(
            run_id="r1",
            load_start_date="2026-06-04",
            load_end_date="2026-06-05",
            jobs=[
                ValidationJob(
                    "fintech",
                    "dag",
                    "dw",
                    "t1",
                    status="compared",
                    verdict="PASS",
                    baseline_s3_uri="s3://b/b.json",
                    emr_s3_uri="s3://b/e.json",
                )
            ],
        )
        baseline = TableBaseline(
            dag="dag",
            table="t1",
            layer="dw",
            load_start_date="2026-06-04",
            load_end_date="2026-06-05",
            schema=[("id", "int")],
            count=1,
            sample_rows=0,
            sample=[],
            order_by_cols=["id"],
            time_pinned_functions=[],
            non_comparable_cols=[],
        )
        emr_payload = {"schema": [["id", "int"]], "count": 1, "sample": []}

        with patch("poller.load_manifest", return_value=manifest):
            with patch("poller.save_manifest"):
                with patch("poller._compare_job") as mock_compare:
                    from models import ValidationResult

                    mock_compare.return_value = ValidationResult(
                        table="dw/t1",
                        baseline_count=1,
                        emr_count=1,
                        count_delta_pct=0.0,
                        schema_match=True,
                        status="PASS",
                    )
                    with patch("poller.finalize_dag_reports", return_value=MagicMock()):
                        with patch("poller.update_session_after_compare"):
                            with patch("poller.RESULTS_FILE") as mock_results:
                                mock_results.write_text = MagicMock()
                                config = WatchConfig(
                                    run_id="r1",
                                    poll_interval_sec=0,
                                    job_timeout_sec=3600,
                                )
                                _, dag_results = run_watch(config)
        self.assertIn("fintech/dag", dag_results)


if __name__ == "__main__":
    unittest.main()
