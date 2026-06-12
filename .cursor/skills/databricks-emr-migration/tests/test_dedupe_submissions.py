"""Tests for duplicate submission guards in async validation."""

import unittest
from unittest import mock

from async_runner import (
    SubmitConfig,
    _pending_jobs_for_dag,
    apply_submit_config_to_manifest,
    merge_manifests,
)
from manifest import RunManifest, ValidationJob, dedupe_manifest_jobs


class TestDedupeManifestJobs(unittest.TestCase):
    def test_keeps_compared_over_pending(self) -> None:
        jobs = [
            ValidationJob("agents", "enrich_brokerage", "enrich", "partner_brokerage", status="pending"),
            ValidationJob(
                "agents",
                "enrich_brokerage",
                "enrich",
                "partner_brokerage",
                status="compared",
                verdict="PASS",
            ),
        ]
        deduped = dedupe_manifest_jobs(jobs)
        self.assertEqual(len(deduped), 1)
        self.assertEqual(deduped[0].status, "compared")

    def test_keeps_running_over_pending(self) -> None:
        jobs = [
            ValidationJob("fintech", "dag", "enrich", "t1", status="pending"),
            ValidationJob("fintech", "dag", "enrich", "t1", status="running", emr_step_id="s-1"),
        ]
        deduped = dedupe_manifest_jobs(jobs)
        self.assertEqual(len(deduped), 1)
        self.assertEqual(deduped[0].status, "running")


class TestApplySubmitConfigToManifest(unittest.TestCase):
    def test_resume_submit_refreshes_load_window(self) -> None:
        manifest = RunManifest(
            run_id="run1",
            load_start_date="2026-06-08",
            load_end_date="2026-06-09",
            databricks_cluster_id="old-db",
            emr_cluster_id="old-emr",
            baseline_git_ref="master",
        )
        config = SubmitConfig(
            domain="agents",
            dag="enrich_brokerage",
            load_start_date="2026-06-09",
            load_end_date="2026-06-10",
            baseline_git_ref="feature-branch",
            databricks_cluster_id="new-db",
            emr_cluster_id="new-emr",
        )
        apply_submit_config_to_manifest(manifest, config)
        self.assertEqual(manifest.load_start_date, "2026-06-09")
        self.assertEqual(manifest.load_end_date, "2026-06-10")
        self.assertEqual(manifest.baseline_git_ref, "feature-branch")
        self.assertEqual(manifest.databricks_cluster_id, "new-db")
        self.assertEqual(manifest.emr_cluster_id, "new-emr")


class TestMergeManifests(unittest.TestCase):
    def test_overlapping_keys_do_not_double_job_count(self) -> None:
        base = RunManifest(
            run_id="run1",
            load_start_date="2026-06-08",
            load_end_date="2026-06-09",
            jobs=[
                ValidationJob("agents", "enrich_brokerage", "enrich", "partner_brokerage", status="running"),
            ],
        )
        other = RunManifest(
            run_id="run1",
            load_start_date="2026-06-08",
            load_end_date="2026-06-09",
            jobs=[
                ValidationJob("agents", "enrich_brokerage", "enrich", "partner_brokerage", status="pending"),
                ValidationJob("fintech", "enrich_billing", "enrich", "contract", status="pending"),
            ],
        )
        merged = merge_manifests([base, other])
        self.assertEqual(len(merged.jobs), 2)
        by_key = {job.key: job for job in merged.jobs}
        self.assertEqual(by_key["agents/enrich_brokerage/enrich/partner_brokerage"].status, "running")


class TestPendingJobsForDag(unittest.TestCase):
    def test_six_duplicate_pending_returns_one(self) -> None:
        manifest = RunManifest(
            run_id="run1",
            load_start_date="2026-06-08",
            load_end_date="2026-06-09",
            jobs=[
                ValidationJob("agents", "enrich_brokerage", "enrich", "partner_brokerage", status="pending")
                for _ in range(6)
            ],
        )
        pending = _pending_jobs_for_dag(manifest, "agents", "enrich_brokerage")
        self.assertEqual(len(pending), 1)

    def test_skips_pending_when_same_key_already_running(self) -> None:
        manifest = RunManifest(
            run_id="run1",
            load_start_date="2026-06-08",
            load_end_date="2026-06-09",
            jobs=[
                ValidationJob("agents", "enrich_brokerage", "enrich", "partner_brokerage", status="running"),
                ValidationJob("agents", "enrich_brokerage", "enrich", "partner_brokerage", status="pending"),
            ],
        )
        pending = _pending_jobs_for_dag(manifest, "agents", "enrich_brokerage")
        self.assertEqual(pending, [])


class TestBaselineCaptureDedup(unittest.TestCase):
    def test_parallel_workers_reuse_cached_baseline(self) -> None:
        import async_runner as runner

        runner._baseline_capture_cache.clear()
        job = ValidationJob("agents", "enrich_brokerage", "enrich", "partner_brokerage")
        config = runner.SubmitConfig(
            domain="agents",
            dag="enrich_brokerage",
            load_start_date="2026-06-08",
            load_end_date="2026-06-09",
        )
        sentinel = object()

        with mock.patch.object(runner, "load_baseline_for_table", return_value=None), mock.patch.object(
            runner, "is_baseline_fresh", return_value=False
        ), mock.patch.object(
            runner,
            "DatabricksAPI",
        ) as mock_api_cls, mock.patch.object(
            runner.DatabricksBaseline,
            "capture_table_baseline",
            return_value=mock.Mock(error=None),
        ) as mock_capture, mock.patch.object(
            runner, "save_baseline_files"
        ):
            mock_api = mock_api_cls.return_value
            mock_api.open_context.return_value = True

            runner._capture_baseline_for_job(config, job, "db-cluster")
            runner._capture_baseline_for_job(config, job, "db-cluster")

        self.assertEqual(mock_capture.call_count, 1)


if __name__ == "__main__":
    unittest.main()
