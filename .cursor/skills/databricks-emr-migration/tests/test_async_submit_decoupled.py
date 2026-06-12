"""Tests for decoupled Databricks baseline + EMR submit."""

import threading
import time
import unittest
from unittest import mock

from async_runner import (
    SubmitConfig,
    _run_baseline_task,
    _run_emr_task,
    resolve_emr_order_by,
    run_submit,
)
from manifest import RunManifest, ValidationJob


class ResolveEmrOrderByTests(unittest.TestCase):
    def test_skip_sample_uses_fallback_without_baseline(self) -> None:
        config = SubmitConfig(
            domain="agents",
            dag="enrich_agent",
            load_start_date="2026-06-08",
            load_end_date="2026-06-09",
            skip_sample=True,
            repo_root=mock.Mock(),
        )
        job = ValidationJob("agents", "enrich_agent", "enrich", "dim_x")
        with mock.patch(
            "async_runner.get_z_order_by", return_value=[]
        ), mock.patch("async_runner._load_metadata_column_names", return_value=[]):
            order_by, parallel = resolve_emr_order_by(config, job, "db-1")
        self.assertEqual(order_by, "1,2,3")
        self.assertTrue(parallel)

    def test_z_order_enables_parallel_sample(self) -> None:
        config = SubmitConfig(
            domain="fintech",
            dag="dag",
            load_start_date="2026-06-08",
            load_end_date="2026-06-09",
            skip_sample=False,
        )
        job = ValidationJob("fintech", "dag", "enrich", "t1")
        with mock.patch(
            "async_runner.get_z_order_by", return_value=["id_contract"]
        ):
            order_by, parallel = resolve_emr_order_by(config, job, "db-1")
        self.assertEqual(order_by, "id_contract")
        self.assertTrue(parallel)


class DecoupledSubmitTaskTests(unittest.TestCase):
    def test_emr_task_can_complete_while_baseline_blocks(self) -> None:
        import async_runner as runner

        runner._baseline_capture_cache.clear()
        manifest = RunManifest(
            run_id="run-decouple",
            load_start_date="2026-06-08",
            load_end_date="2026-06-09",
            jobs=[
                ValidationJob(
                    "agents",
                    "enrich_agent",
                    "enrich",
                    "dim_x",
                    status="submitted",
                )
            ],
        )
        config = SubmitConfig(
            domain="agents",
            dag="enrich_agent",
            load_start_date="2026-06-08",
            load_end_date="2026-06-09",
            skip_sample=True,
            run_id="run-decouple",
        )
        stager = mock.Mock()
        stager.log_uri_for.return_value = "s3://bucket/log"
        baseline_started = threading.Event()
        release_baseline = threading.Event()

        def slow_capture(*_args, **_kwargs):
            baseline_started.set()
            release_baseline.wait(timeout=5)
            return mock.Mock(error=None), None

        emr_done = threading.Event()

        def fast_emr(*_args, **_kwargs):
            emr_done.set()
            return "s-123", None

        def fake_update(_manifest, job, **kwargs):
            for index, existing in enumerate(manifest.jobs):
                if existing.key == job.key:
                    manifest.jobs[index] = job

        with mock.patch.object(
            runner, "_capture_baseline_for_job", side_effect=slow_capture
        ), mock.patch.object(
            runner, "_submit_emr_for_job", side_effect=fast_emr
        ), mock.patch.object(
            runner, "load_pinned_sql", return_value="SELECT 1"
        ), mock.patch.object(
            runner, "update_job", side_effect=fake_update
        ), mock.patch.object(
            runner, "upload_text_to_s3"
        ):
            emr_future = threading.Thread(
                target=_run_emr_task,
                args=(
                    config,
                    manifest,
                    manifest.jobs[0].key,
                    "j-emr",
                    "db-1",
                    stager,
                ),
            )
            emr_future.start()
            self.assertTrue(emr_done.wait(timeout=2), "EMR should finish without baseline")
            baseline_started.wait(timeout=2)
            release_baseline.set()
            emr_future.join(timeout=2)

        job = manifest.jobs[0]
        self.assertEqual(job.emr_step_id, "s-123")
        self.assertIn(job.status, {"running", "baseline_done"})


class RunSubmitRoutingTests(unittest.TestCase):
    def test_run_submit_uses_decoupled_pools_when_skip_sample(self) -> None:
        config = SubmitConfig(
            domain="agents",
            dag="enrich_agent",
            load_start_date="2026-06-08",
            load_end_date="2026-06-09",
            databricks_cluster_id="db-1",
            emr_cluster_id="j-emr",
            skip_sample=True,
            table_filter="dim_x",
            run_id="run-route",
        )
        with mock.patch(
            "async_runner.resolve_databricks_cluster", return_value="db-1"
        ), mock.patch(
            "async_runner.is_emr_cluster_reusable", return_value=(True, "WAITING")
        ), mock.patch(
            "async_runner.resolve_validation_emr_cluster", return_value="j-emr"
        ), mock.patch(
            "async_runner.ensure_aws_credentials"
        ), mock.patch(
            "async_runner.load_manifest", side_effect=FileNotFoundError
        ), mock.patch(
            "async_runner.save_manifest"
        ), mock.patch(
            "async_runner.save_session"
        ), mock.patch(
            "async_runner.load_session", return_value={}
        ), mock.patch(
            "async_runner.discover_tables", return_value=[("dim_x", "enrich")]
        ), mock.patch(
            "async_runner.resolve_emr_order_by", return_value=("id_x", True)
        ), mock.patch(
            "async_runner._run_baseline_task"
        ) as mock_baseline, mock.patch(
            "async_runner._run_emr_task"
        ) as mock_emr, mock.patch(
            "async_runner.as_completed", side_effect=lambda futures: list(futures)
        ), mock.patch(
            "async_runner.ThreadPoolExecutor"
        ) as mock_executor_cls:
            mock_db_pool = mock.MagicMock()
            mock_emr_pool = mock.MagicMock()
            mock_executor_cls.side_effect = [mock_db_pool, mock_emr_pool]
            mock_db_pool.__enter__.return_value = mock_db_pool
            mock_emr_pool.__enter__.return_value = mock_emr_pool
            completed = mock.Mock()
            completed.result.return_value = []
            mock_db_pool.submit.return_value = completed
            mock_emr_pool.submit.return_value = completed

            run_submit(config)

        self.assertEqual(mock_db_pool.submit.call_count, 1)
        self.assertEqual(mock_emr_pool.submit.call_count, 1)


if __name__ == "__main__":
    unittest.main()
