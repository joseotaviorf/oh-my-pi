import time
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from manual_check import MANUAL_CHECK_STATUS, is_manual_check_error, manual_check_message
from manifest import ValidationJob
from poller import WatchConfig, _manual_check_reason, _result_from_terminal_job


class TestManualCheck(unittest.TestCase):
    def test_is_manual_check_error(self) -> None:
        self.assertTrue(is_manual_check_error("Command timeout after 1800s"))
        self.assertTrue(is_manual_check_error(manual_check_message("heavy query")))
        self.assertFalse(is_manual_check_error("TABLE_OR_VIEW_NOT_FOUND"))

    def test_manual_check_message_prefix(self) -> None:
        self.assertTrue(
            manual_check_message("baseline slow").startswith("Manual check required:")
        )

    def test_result_from_timeout_job_is_manual(self) -> None:
        job = ValidationJob(
            "fintech",
            "dw_credit_analysis",
            "dw",
            "fact_proposal_credit_flows",
            status="manual_check",
            error=manual_check_message("exceeded manual check threshold (1800s)"),
        )
        result = _result_from_terminal_job(job)
        self.assertEqual(result.status, MANUAL_CHECK_STATUS)
        self.assertIn("Manual check required", result.message)

    def test_manual_check_reason_before_hard_timeout(self) -> None:
        emr_started = (
            datetime.now(timezone.utc) - timedelta(seconds=1000)
        ).replace(microsecond=0).isoformat()
        job = ValidationJob(
            "fintech",
            "dag",
            "dw",
            "heavy",
            status="running",
            emr_submitted_at=emr_started,
        )
        config = WatchConfig(
            run_id="r1",
            manual_check_timeout_sec=900,
            job_timeout_sec=3600,
        )
        reason = _manual_check_reason(job, config, time.time() - 1000)
        self.assertIsNotNone(reason)
        self.assertIn("manual check threshold", reason or "")

    def test_manual_check_skips_jobs_still_in_baseline(self) -> None:
        queued = (
            datetime.now(timezone.utc) - timedelta(seconds=1000)
        ).replace(microsecond=0).isoformat()
        job = ValidationJob(
            "fintech",
            "dag",
            "dw",
            "heavy",
            status="submitted",
            submitted_at=queued,
        )
        config = WatchConfig(run_id="r1", manual_check_timeout_sec=120)
        self.assertIsNone(_manual_check_reason(job, config, time.time()))

    def test_manual_check_waits_for_watch_clock_not_emr_submit(self) -> None:
        emr_started = (
            datetime.now(timezone.utc) - timedelta(seconds=200)
        ).replace(microsecond=0).isoformat()
        job = ValidationJob(
            "fintech",
            "dag",
            "dw",
            "dim_credit_analysis",
            status="running",
            emr_submitted_at=emr_started,
            emr_step_id="s-123",
        )
        config = WatchConfig(run_id="r1", manual_check_timeout_sec=120)
        watch_started = time.time()
        with patch("poller.emr_step_state", return_value="PENDING"):
            self.assertIsNone(
                _manual_check_reason(job, config, watch_started, cluster_id="j-CLUSTER")
            )


if __name__ == "__main__":
    unittest.main()
