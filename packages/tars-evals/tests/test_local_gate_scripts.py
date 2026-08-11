"""Tests for the local mirrors of the .woodpecker/tars_evals.yml steps.

``uv`` and ``git`` are faked on ``PATH`` (same approach as
``test_queue_script.py``) so these stay offline and cost nothing.
"""

import os
import shutil
import subprocess
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[1] / "scripts"

FAKE_UV = """#!/usr/bin/env bash
printf '%s\\n' "$*" >>"$UV_CALL_LOG"
case "$*" in
  *changed_dataset_stems.py*)
    prev=""
    for arg in "$@"; do
      case "$prev" in
        --write-eval-stems) printf '%b' "${FAKE_EVAL_STEMS:-}" >"$arg" ;;
        --write-scope-stems) printf '%b' "${FAKE_SCOPE_STEMS:-}" >"$arg" ;;
      esac
      prev="$arg"
    done
    exit "${FAKE_RESOLVE_RC:-0}"
    ;;
  *generate_datasets_from_context_docs.py*)
    exit "${FAKE_GENERATE_RC:-0}"
    ;;
esac
"""

FAKE_GIT = """#!/usr/bin/env bash
printf '%s\\n' "$*" >>"$GIT_CALL_LOG"
case "$1" in
  merge-base)
    if [[ -n "${FAKE_MERGE_BASE:-}" ]]; then echo "$FAKE_MERGE_BASE"; exit 0; fi
    exit 128
    ;;
  rev-parse) echo "${FAKE_REPO_ROOT:-/nonexistent}" ;;
  diff) exit "${FAKE_GIT_DIFF_RC:-0}" ;;
esac
"""

FAKE_QUEUE = """#!/usr/bin/env bash
# One argument per line, so a stem containing a space is provably one arg.
printf '%s\\n' "$@" >>"$QUEUE_CALL_LOG"
exit "${FAKE_QUEUE_RC:-0}"
"""


def _prepare(tmp_path: Path, script_name: str) -> tuple[Path, dict[str, str]]:
    package_root = tmp_path / "package"
    scripts_dir = package_root / "scripts"
    scripts_dir.mkdir(parents=True)
    shutil.copy(SCRIPTS_DIR / script_name, scripts_dir / script_name)
    (scripts_dir / script_name).chmod(0o755)
    (package_root / "datasets").mkdir()

    queue = scripts_dir / "run_dataset_queue.sh"
    queue.write_text(FAKE_QUEUE)
    queue.chmod(0o755)

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for name, body in (("uv", FAKE_UV), ("git", FAKE_GIT)):
        fake = bin_dir / name
        fake.write_text(body)
        fake.chmod(0o755)

    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{bin_dir}{os.pathsep}{env['PATH']}",
            "UV_CALL_LOG": str(tmp_path / "uv-calls.log"),
            "GIT_CALL_LOG": str(tmp_path / "git-calls.log"),
            "QUEUE_CALL_LOG": str(tmp_path / "queue-calls.log"),
            "TARS_EVAL_STEMS_FILE": str(package_root / ".tars-eval-stems"),
            "TARS_EVAL_SCOPE_FILE": str(package_root / ".tars-eval-expected-stems"),
        }
    )
    for key in ("TARS_EVAL_BASE", "TARS_EVAL_HEAD", "DRY_RUN"):
        env.pop(key, None)
    return scripts_dir / script_name, env


def _run(script: Path, env: dict[str, str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        [str(script)], capture_output=True, text=True, env=env, check=False
    )


def _log(env: dict[str, str], key: str) -> list[str]:
    path = Path(env[key])
    return path.read_text().splitlines() if path.exists() else []


# --------------------------------------------------------------------------
# eval_changed.sh
# --------------------------------------------------------------------------


def test_eval_changed_never_runs_the_queue_on_an_empty_stem_list(tmp_path: Path):
    """The guard is load-bearing: run_dataset_queue.sh with no arguments
    evaluates *every* dataset, so an empty scope must short-circuit."""
    script, env = _prepare(tmp_path, "eval_changed.sh")
    Path(env["TARS_EVAL_STEMS_FILE"]).write_text("")

    result = _run(script, env)

    assert result.returncode == 0
    assert "nothing to evaluate" in result.stdout
    assert _log(env, "QUEUE_CALL_LOG") == []


def test_eval_changed_short_circuits_when_the_stem_file_is_missing(tmp_path: Path):
    script, env = _prepare(tmp_path, "eval_changed.sh")

    result = _run(script, env)

    assert result.returncode == 0
    assert _log(env, "QUEUE_CALL_LOG") == []


def test_eval_changed_passes_each_stem_as_its_own_argument(tmp_path: Path):
    """Line-based reading, so a stem containing a space is not word-split
    into two bogus stems (CI's `$(cat …)` form would split it)."""
    script, env = _prepare(tmp_path, "eval_changed.sh")
    Path(env["TARS_EVAL_STEMS_FILE"]).write_text("alpha\nalpha space\n\nzeta\n")

    result = _run(script, env)

    assert result.returncode == 0
    assert _log(env, "QUEUE_CALL_LOG") == ["alpha", "alpha space", "zeta"]


def test_eval_changed_propagates_a_failing_gate(tmp_path: Path):
    script, env = _prepare(tmp_path, "eval_changed.sh")
    Path(env["TARS_EVAL_STEMS_FILE"]).write_text("alpha\n")
    env["FAKE_QUEUE_RC"] = "1"

    result = _run(script, env)

    assert result.returncode == 1


def test_eval_changed_distinguishes_a_broken_harness_from_a_failed_gate(
    tmp_path: Path,
):
    """Exit 2 (harness broke) must survive intact rather than collapse to 1."""
    script, env = _prepare(tmp_path, "eval_changed.sh")
    Path(env["TARS_EVAL_STEMS_FILE"]).write_text("alpha\n")
    env["FAKE_QUEUE_RC"] = "2"

    result = _run(script, env)

    assert result.returncode == 2


def test_eval_changed_echoes_per_stem_gate_reports_after_a_failure(tmp_path: Path):
    script, env = _prepare(tmp_path, "eval_changed.sh")
    Path(env["TARS_EVAL_STEMS_FILE"]).write_text("alpha\n")
    env["FAKE_QUEUE_RC"] = "1"
    report = script.parent.parent / "logs" / "per_dataset" / "alpha" / "gate_report.txt"
    report.parent.mkdir(parents=True)
    report.write_text("SAMPLE alpha-1 scored 3/5\n")

    result = _run(script, env)

    assert result.returncode == 1
    assert "SAMPLE alpha-1 scored 3/5" in result.stdout


# --------------------------------------------------------------------------
# check_dataset_drift.sh
# --------------------------------------------------------------------------


def test_drift_check_skips_generation_on_an_empty_scope(tmp_path: Path):
    script, env = _prepare(tmp_path, "check_dataset_drift.sh")
    Path(env["TARS_EVAL_SCOPE_FILE"]).write_text("")

    result = _run(script, env)

    assert result.returncode == 0
    assert "nothing to drift-check" in result.stdout
    assert _log(env, "UV_CALL_LOG") == []


def test_drift_check_regenerates_in_scope_stems_skipping_hand_authored(
    tmp_path: Path,
):
    """--skip-hand-authored is required here and only here: a hand-authored
    dataset is never regenerated, so it cannot drift, and failing on one would
    leave the author no change that could turn the PR green."""
    script, env = _prepare(tmp_path, "check_dataset_drift.sh")
    Path(env["TARS_EVAL_SCOPE_FILE"]).write_text("alpha\n")

    result = _run(script, env)

    assert result.returncode == 0
    calls = _log(env, "UV_CALL_LOG")
    assert len(calls) == 1
    assert "generate_datasets_from_context_docs.py" in calls[0]
    assert f"--stems-file {env['TARS_EVAL_SCOPE_FILE']}" in calls[0]
    assert "--skip-hand-authored" in calls[0]


def test_drift_check_fails_when_regeneration_changes_committed_yaml(tmp_path: Path):
    script, env = _prepare(tmp_path, "check_dataset_drift.sh")
    Path(env["TARS_EVAL_SCOPE_FILE"]).write_text("alpha\n")
    env["FAKE_GIT_DIFF_RC"] = "1"

    result = _run(script, env)

    assert result.returncode == 1
    assert "out of sync" in result.stderr


# --------------------------------------------------------------------------
# resolve_eval_scope.sh
# --------------------------------------------------------------------------


def test_resolve_scope_defaults_to_the_merge_base_with_origin_master(
    tmp_path: Path,
):
    """`git diff A...B` == `git diff $(git merge-base A B) B`, so passing the
    merge base gives the same range the PR gate diffs."""
    script, env = _prepare(tmp_path, "resolve_eval_scope.sh")
    env["FAKE_MERGE_BASE"] = "cafef00d"
    env["FAKE_EVAL_STEMS"] = "alpha\n"
    env["FAKE_SCOPE_STEMS"] = "alpha\nbeta\n"

    result = _run(script, env)

    assert result.returncode == 0, result.stderr
    calls = _log(env, "UV_CALL_LOG")
    assert "--base cafef00d" in calls[0]
    assert "alpha" in result.stdout
    assert "beta" in result.stdout


def test_resolve_scope_honours_an_explicit_base(tmp_path: Path):
    script, env = _prepare(tmp_path, "resolve_eval_scope.sh")
    env["FAKE_MERGE_BASE"] = "cafef00d"
    env["TARS_EVAL_BASE"] = "HEAD~3"
    env["TARS_EVAL_HEAD"] = "HEAD~1"

    result = _run(script, env)

    assert result.returncode == 0, result.stderr
    calls = _log(env, "UV_CALL_LOG")
    assert "--base HEAD~3" in calls[0]
    assert "--head HEAD~1" in calls[0]
    assert "cafef00d" not in calls[0]


def test_resolve_scope_falls_back_to_auto_detection_without_origin_master(
    tmp_path: Path,
):
    """A fresh clone with no origin/master must still resolve, letting
    changed_dataset_stems.py apply its own diff-base precedence."""
    script, env = _prepare(tmp_path, "resolve_eval_scope.sh")
    env.pop("FAKE_MERGE_BASE", None)

    result = _run(script, env)

    assert result.returncode == 0, result.stderr
    calls = _log(env, "UV_CALL_LOG")
    assert "--base" not in calls[0]
    assert "<auto-detected>" in result.stdout


def test_resolve_scope_propagates_a_resolver_failure(tmp_path: Path):
    """Exit 2 = structural error (bad diff range, or the sample budget guard
    tripped); it must fail the local gate the same way it fails CI."""
    script, env = _prepare(tmp_path, "resolve_eval_scope.sh")
    env["FAKE_RESOLVE_RC"] = "2"

    result = _run(script, env)

    assert result.returncode == 2


def test_resolve_scope_warns_about_uncommitted_context_docs(tmp_path: Path):
    """A committed-diff resolver cannot see the working tree, so an author who
    edits a doc and runs the gate before committing gets an empty scope."""
    script, env = _prepare(tmp_path, "resolve_eval_scope.sh")
    env["FAKE_MERGE_BASE"] = "cafef00d"
    env["FAKE_GIT_DIFF_RC"] = "1"

    result = _run(script, env)

    assert result.returncode == 0, result.stderr
    assert "uncommitted changes under docs/llm_context" in result.stderr
