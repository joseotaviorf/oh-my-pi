"""Tests for batch_validate resume, reset-stale, and watch exit codes."""

from __future__ import annotations

import unittest
from unittest import mock

import batch_validate as batch_module
from models import ValidationResult


def _result(table: str, status: str = "PASS", message: str = "ok") -> ValidationResult:
    return ValidationResult(
        table=table,
        baseline_count=100,
        emr_count=100,
        count_delta_pct=0.0,
        schema_match=status != "FAIL",
        status=status,
        message=message,
    )


class TestBatchValidate(unittest.TestCase):
    def test_run_watch_exits_zero_on_parity_fail_only(self) -> None:
        dag_results = {
            "fintech/enrich_bank": [
                _result("a"),
                _result("b", "FAIL", "count_delta=83.2% schema=ok"),
            ]
        }
        args = mock.Mock(
            run_id="run-1",
            emr_env="prod",
            poll_interval=15,
            job_timeout=3600,
            manual_check_timeout=300,
            global_timeout=None,
            skip_sample=True,
        )
        with (
            mock.patch.object(batch_module, "load_session", return_value={"active_run_id": "run-1"}),
            mock.patch.object(batch_module, "run_watch", return_value=(mock.Mock(), dag_results)),
            mock.patch.object(batch_module, "print_batch_gate_summary") as print_summary,
        ):
            exit_code = batch_module._run_watch(args)

        self.assertEqual(exit_code, 0)
        print_summary.assert_called_once_with(dag_results)

    def test_run_watch_exits_nonzero_on_syntax_fail(self) -> None:
        dag_results = {
            "agents/enrich_agent": [
                _result("a", "FAIL", "[PARSE_SYNTAX_ERROR] near 'SELECT'"),
            ]
        }
        args = mock.Mock(
            run_id="run-1",
            emr_env="prod",
            poll_interval=15,
            job_timeout=3600,
            manual_check_timeout=300,
            global_timeout=None,
            skip_sample=True,
        )
        with (
            mock.patch.object(batch_module, "load_session", return_value={"active_run_id": "run-1"}),
            mock.patch.object(batch_module, "run_watch", return_value=(mock.Mock(), dag_results)),
            mock.patch.object(batch_module, "print_batch_gate_summary"),
        ):
            exit_code = batch_module._run_watch(args)

        self.assertEqual(exit_code, 1)

    def test_batch_submit_skips_dags_already_in_manifest(self) -> None:
        args = mock.Mock(
            run_id="run-1",
            emr_env="prod",
            reset_stale=False,
            git_ref="master",
            profile="PROD",
            cluster="db-1",
            staging_uri=None,
            skip_sample=True,
            timeout=300,
            max_parallel=5,
            no_create_emr=False,
            new_emr_session=False,
        )
        dag_list = [("agents", "enrich_agent"), ("fintech", "enrich_billing")]
        job = mock.Mock(domain="agents", dag="enrich_agent")
        manifest = mock.Mock(jobs=[job], manifest_s3_uri="s3://bucket/manifest.json", run_id="run-1")

        with (
            mock.patch.object(batch_module, "load_session", return_value={"emr_cluster_id": "j-1"}),
            mock.patch.object(batch_module, "save_session"),
            mock.patch.object(batch_module, "_submitted_dag_keys", return_value={("agents", "enrich_agent")}),
            mock.patch.object(
                batch_module,
                "discover_tables_needing_translation",
                return_value=([("dim_a", "enrich")], []),
            ),
            mock.patch.object(batch_module, "run_submit", return_value=manifest) as run_submit,
        ):
            run_id = batch_module._run_batch_submit(args, dag_list)

        self.assertEqual(run_id, "run-1")
        run_submit.assert_called_once()
        submit_config = run_submit.call_args.args[0]
        self.assertEqual(submit_config.domain, "fintech")
        self.assertEqual(submit_config.dag, "enrich_billing")

    def test_maybe_reset_stale_persists_manifest(self) -> None:
        manifest = mock.Mock()
        with (
            mock.patch.object(batch_module, "load_manifest", return_value=manifest),
            mock.patch.object(batch_module, "reset_stale_jobs", return_value=2),
            mock.patch.object(batch_module, "save_manifest") as save_manifest,
        ):
            batch_module._maybe_reset_stale("run-1", emr_env="prod")

        save_manifest.assert_called_once_with(manifest, emr_env="prod")


if __name__ == "__main__":
    unittest.main()
