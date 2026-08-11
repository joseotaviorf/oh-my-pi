"""Layer 3 — real CLI process invocation for changed_dataset_stems.py.

subprocess.run([sys.executable, SCRIPT, ...]) exercises the actual exit-code
and stdout contract a CI step depends on, plus one end-to-end wiring check
that changed_dataset_stems.py's stdout feeds directly into
run_dataset_queue.sh's positional stem arguments (Story 4's seam) with
DRY_RUN=1, so no real model is ever touched.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "changed_dataset_stems.py"
QUEUE_SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "run_dataset_queue.sh"
PKG_ROOT = Path(__file__).resolve().parents[1]

_METRIC_A = "docs/llm_context/metric_entities/metric_a.md"
_METRIC_A_DOC = "# Metric A\n\n## Overview\n\nv1\n\n## Golden Queries\n\nn/a\n"
_DATASET_A_YAML = "items:\n- id: a-1\n  question: q\n  expected_query: sql\n"


def _run_cli(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
    )


def _add_metric_a(repo) -> None:
    repo.write(_METRIC_A, _METRIC_A_DOC)
    repo.write("datasets/metric_a.yaml", _DATASET_A_YAML)
    repo.commit("add metric_a")


def test_cli_stdout_contract_empty_diff_exits_zero(tmp_git_repo):
    repo = tmp_git_repo

    result = _run_cli(
        "--repo-root",
        str(repo.path),
        "--datasets-dir",
        str(repo.path / "datasets"),
        "--base",
        "HEAD",
        "--head",
        "HEAD",
    )

    assert result.returncode == 0
    assert result.stdout == ""


def test_cli_reports_eval_stem_for_modified_metric_doc(tmp_git_repo):
    repo = tmp_git_repo
    _add_metric_a(repo)

    result = _run_cli(
        "--repo-root",
        str(repo.path),
        "--datasets-dir",
        str(repo.path / "datasets"),
        "--base",
        "HEAD~1",
        "--head",
        "HEAD",
    )

    assert result.returncode == 0
    assert result.stdout == "metric_a\n"


def test_cli_exits_two_on_budget_overflow(tmp_git_repo):
    repo = tmp_git_repo
    _add_metric_a(repo)

    result = _run_cli(
        "--repo-root",
        str(repo.path),
        "--datasets-dir",
        str(repo.path / "datasets"),
        "--base",
        "HEAD~1",
        "--head",
        "HEAD",
        "--max-samples",
        "0",
    )

    assert result.returncode == 2
    assert "sample budget exceeded" in result.stderr


def test_cli_output_wires_into_run_dataset_queue_dry_run(tmp_git_repo):
    repo = tmp_git_repo
    _add_metric_a(repo)

    cli_result = _run_cli(
        "--repo-root",
        str(repo.path),
        "--datasets-dir",
        str(repo.path / "datasets"),
        "--base",
        "HEAD~1",
        "--head",
        "HEAD",
    )
    assert cli_result.returncode == 0
    stems = cli_result.stdout.split()
    assert stems == ["metric_a"]

    env = os.environ.copy()
    env["DRY_RUN"] = "1"
    queue_result = subprocess.run(
        [
            "bash",
            str(QUEUE_SCRIPT),
            "--datasets-dir",
            str(repo.path / "datasets"),
            *stems,
        ],
        cwd=PKG_ROOT,
        env=env,
        capture_output=True,
        text=True,
    )

    assert queue_result.returncode == 0
    assert "metric_a" in queue_result.stdout
    assert "DRY_RUN: would evaluate 1 dataset(s)" in queue_result.stderr
