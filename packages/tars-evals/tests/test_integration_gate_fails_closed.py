"""Real end-to-end integration test for the fail-closed suite gate.

Unlike test_queue_script.py, this does NOT fake the `uv` binary — it runs
the actual `run_dataset_queue.sh` -> `run_single_dataset_eval.py` ->
`build_rollup.py` chain via the real CLI. To stay credential-free and
network-free, both models are pointed at Inspect AI's built-in
`mockllm/model` (see README "Verifying the plumbing without real
credentials"): the mock model never calls any tool, so tars never produces
SQL to grade, giving a deterministic NO-SQL result the gate must legitimately
fail — proving the whole real chain fails closed end-to-end.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = PACKAGE_ROOT / "config.yaml"
QUEUE_SCRIPT = PACKAGE_ROOT / "scripts" / "run_dataset_queue.sh"
_STEM = "_integration_mock_gate_fail"


@pytest.fixture
def _mocked_models():
    """Temporarily point tars_model/judge_model at mockllm/model — the same
    technique the README documents for manually verifying the harness wiring
    without a LiteLLM key. Always restores the real config.yaml afterward."""
    original = CONFIG_PATH.read_text(encoding="utf-8")
    mocked = re.sub(r"(?m)^tars_model:.*$", "tars_model: mockllm/model", original)
    mocked = re.sub(r"(?m)^judge_model:.*$", "judge_model: mockllm/model", mocked)
    assert mocked != original, "expected tars_model/judge_model keys in config.yaml"
    CONFIG_PATH.write_text(mocked, encoding="utf-8")
    try:
        yield
    finally:
        CONFIG_PATH.write_text(original, encoding="utf-8")


@pytest.fixture
def _throwaway_dataset():
    """A single-item dataset stem, removed after the test. logs/ and
    gate_summary.json are gitignored scratch that run_dataset_queue.sh
    already overwrites on every invocation, so only the tracked dataset file
    and this stem's own log dir need explicit cleanup."""
    dataset_path = PACKAGE_ROOT / "datasets" / f"{_STEM}.yaml"
    dataset_path.write_text(
        "items:\n"
        "- id: only\n"
        "  question: What is the answer?\n"
        "  expected_query: SELECT 1\n",
        encoding="utf-8",
    )
    log_dir = PACKAGE_ROOT / "logs" / "per_dataset" / _STEM
    try:
        yield dataset_path
    finally:
        dataset_path.unlink(missing_ok=True)
        shutil.rmtree(log_dir, ignore_errors=True)


@pytest.fixture
def _skill_dir(tmp_path: Path) -> Path:
    skill_dir = tmp_path / "skill"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text("# tars\n", encoding="utf-8")
    (skill_dir / "scripts").mkdir()
    return skill_dir


def test_real_cli_fails_closed_on_a_genuinely_failing_gate(
    _mocked_models, _throwaway_dataset, _skill_dir
):
    env = os.environ.copy()
    env.update(
        {
            "OPENAI_API_KEY": "dummy-mock-key",
            "LITELLM_API_KEY": "dummy-mock-key",
            "TARS_SKILL_DIR": str(_skill_dir),
            "TARS_EVAL_WORKERS": "1",
        }
    )

    result = subprocess.run(
        [str(QUEUE_SCRIPT), _STEM],
        cwd=PACKAGE_ROOT,
        capture_output=True,
        text=True,
        env=env,
        check=False,
        timeout=120,
    )

    assert result.returncode == 1, (
        f"expected the suite gate to fail closed (exit 1); "
        f"stdout={result.stdout}\nstderr={result.stderr}"
    )
    assert "suite gate failed" in result.stderr

    summary_path = PACKAGE_ROOT / "logs" / "per_dataset" / _STEM / "summary.json"
    assert summary_path.is_file()
    summary = json.loads(summary_path.read_text())
    assert summary["passed"] is False
    assert summary["samples"][0]["status"] == "NO-SQL"

    gate_summary = json.loads((PACKAGE_ROOT / "gate_summary.json").read_text())
    assert gate_summary["passed"] is False
