"""Unit tests for Inspect-log S3 archive prefix + upload helper."""

from __future__ import annotations

import importlib.util
from datetime import datetime, timezone
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "upload_inspect_logs_s3.py"


@pytest.fixture(scope="module")
def upload_mod():
    spec = importlib.util.spec_from_file_location("upload_inspect_logs_s3", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_build_prefix_for_pull_request(upload_mod):
    prefix = upload_mod.build_prefix(
        now=datetime(2026, 8, 7, tzinfo=timezone.utc),
        pipeline_event="pull_request",
        pull_request="27321",
        commit_sha="abcdef1234567890",
        pipeline_number="89291",
    )
    assert prefix == "evals/inspect/2026/08/07/pr-27321/pipeline-89291"


def test_build_prefix_for_push(upload_mod):
    prefix = upload_mod.build_prefix(
        now=datetime(2026, 8, 7, tzinfo=timezone.utc),
        pipeline_event="push",
        commit_sha="abcdef1234567890deadbeef",
        pipeline_number="100",
    )
    assert prefix == "evals/inspect/2026/08/07/push-abcdef123456/pipeline-100"


def test_upload_directory_uploads_nested_and_extra_files(upload_mod, tmp_path: Path):
    source = tmp_path / "logs" / "per_dataset" / "eval_fixture_metric"
    inspect_dir = source / "inspect_logs"
    inspect_dir.mkdir(parents=True)
    (source / "gate_report.txt").write_text("GATE PASS\n", encoding="utf-8")
    (inspect_dir / "run.eval").write_text("eval", encoding="utf-8")
    extra = tmp_path / "gate_summary.json"
    extra.write_text('{"passed": true}\n', encoding="utf-8")

    calls: list[tuple[str, str, str]] = []

    class FakeS3:
        def upload_file(self, filename, bucket, key):
            calls.append((filename, bucket, key))

    uploaded = upload_mod.upload_directory(
        bucket="5a-tars-prod-data",
        prefix="evals/inspect/2026/08/07/pr-1/pipeline-2",
        source=tmp_path / "logs" / "per_dataset",
        extra_files=[extra],
        s3_client=FakeS3(),
    )

    keys = sorted(key for _, _, key in calls)
    assert keys == [
        "evals/inspect/2026/08/07/pr-1/pipeline-2/eval_fixture_metric/gate_report.txt",
        "evals/inspect/2026/08/07/pr-1/pipeline-2/eval_fixture_metric/inspect_logs/run.eval",
        "evals/inspect/2026/08/07/pr-1/pipeline-2/gate_summary.json",
    ]
    assert all(uri.startswith("s3://5a-tars-prod-data/") for uri in uploaded)
    assert len(uploaded) == 3
