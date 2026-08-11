import os
import shutil
import subprocess
from pathlib import Path

QUEUE_SCRIPT = (
    Path(__file__).resolve().parents[1] / "scripts" / "run_dataset_queue.sh"
)


def _prepare_queue(tmp_path: Path) -> tuple[Path, dict[str, str]]:
    package_root = tmp_path / "package"
    scripts_dir = package_root / "scripts"
    scripts_dir.mkdir(parents=True)
    shutil.copy(QUEUE_SCRIPT, scripts_dir / QUEUE_SCRIPT.name)
    (package_root / "datasets").mkdir()
    (package_root / "datasets" / "alpha.yaml").write_text("items: []\n")

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    fake_uv = bin_dir / "uv"
    fake_uv.write_text(
        """#!/usr/bin/env bash
printf '%s\n' "$*" >>"$UV_CALL_LOG"
case "$*" in
  *list_dataset_stems.py*)
    if [[ "${FAKE_LIST_RC:-0}" -ne 0 ]]; then
      exit "$FAKE_LIST_RC"
    fi
    printf '%b' "${FAKE_STEMS:-alpha\\n}"
    ;;
  *run_single_dataset_eval.py*)
    exit "${FAKE_EVAL_RC:-0}"
    ;;
  *build_rollup.py*)
    if [[ "${FAKE_ROLLUP_RC:-0}" == "1" ]]; then
      # exit 1 = a valid run whose gate legitimately failed (mirrors the
      # real build_rollup.py contract): it writes gate_summary.json before
      # returning, so the queue's check_gate.py re-check has something to read.
      printf '{"passed": false}' >gate_summary.json
    fi
    exit "${FAKE_ROLLUP_RC:-0}"
    ;;
  *check_gate.py*)
    echo "FAKE_CHECK_GATE_REPORT" >&2
    exit 1
    ;;
esac
"""
    )
    fake_uv.chmod(0o755)

    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{bin_dir}{os.pathsep}{env['PATH']}",
            "UV_CALL_LOG": str(tmp_path / "uv-calls.log"),
            "OPENAI_API_KEY": "test-key",
        }
    )
    return scripts_dir / QUEUE_SCRIPT.name, env


def test_queue_uses_python_discovery_with_deterministic_unusual_stems(
    tmp_path: Path,
):
    queue, env = _prepare_queue(tmp_path)
    env["DRY_RUN"] = "1"
    env["FAKE_STEMS"] = "alpha space\nzeta-name\n"

    result = subprocess.run(
        [str(queue)],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode == 0
    assert result.stdout.splitlines() == ["alpha space", "zeta-name"]
    calls = Path(env["UV_CALL_LOG"]).read_text()
    assert "scripts/list_dataset_stems.py" in calls


def test_queue_stops_when_stem_validation_fails(tmp_path: Path):
    queue, env = _prepare_queue(tmp_path)
    env["DRY_RUN"] = "1"
    env["FAKE_LIST_RC"] = "1"

    result = subprocess.run(
        [str(queue), "../alpha"],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode != 0


def test_queue_removes_stale_summary_before_failed_rerun(tmp_path: Path):
    queue, env = _prepare_queue(tmp_path)
    env["FAKE_EVAL_RC"] = "7"
    env["FAKE_ROLLUP_RC"] = "1"
    package_root = queue.parent.parent
    stale_summary = (
        package_root / "logs" / "per_dataset" / "alpha" / "summary.json"
    )
    stale_summary.parent.mkdir(parents=True)
    stale_summary.write_text('{"stem": "alpha", "passed": true}\n')
    stale_rollup = package_root / "logs" / "per_dataset" / "rollup.json"
    stale_rollup.write_text('{"datasets_completed": 1}\n')
    stale_gate = package_root / "gate_summary.json"
    stale_gate.write_text('{"passed": true}\n')

    result = subprocess.run(
        [str(queue), "alpha"],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode != 0
    assert not stale_summary.exists()
    assert not stale_rollup.exists()
    assert not stale_gate.exists()


def test_queue_surfaces_check_gate_report_on_a_legitimate_gate_failure(
    tmp_path: Path,
):
    """rc=1 (a valid run whose gate legitimately failed, per build_rollup.py's
    exit-code convention) should trigger the richer check_gate.py report, not
    just the bare 'suite gate failed' line."""
    queue, env = _prepare_queue(tmp_path)
    env["FAKE_EVAL_RC"] = "0"
    env["FAKE_ROLLUP_RC"] = "1"

    result = subprocess.run(
        [str(queue), "alpha"],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode != 0
    assert "suite gate failed" in result.stderr
    assert "FAKE_CHECK_GATE_REPORT" in result.stderr
    calls = Path(env["UV_CALL_LOG"]).read_text().splitlines()
    assert any(call.endswith("scripts/check_gate.py gate_summary.json") for call in calls)


def test_queue_skips_check_gate_report_on_a_structural_rollup_error(
    tmp_path: Path,
):
    """rc=2 (structural error — no gate_summary.json was ever written) must
    not attempt to re-check a gate summary that doesn't exist."""
    queue, env = _prepare_queue(tmp_path)
    env["FAKE_EVAL_RC"] = "0"
    env["FAKE_ROLLUP_RC"] = "2"

    result = subprocess.run(
        [str(queue), "alpha"],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode == 2
    assert "suite gate failed" in result.stderr
    assert "FAKE_CHECK_GATE_REPORT" not in result.stderr
    calls = Path(env["UV_CALL_LOG"]).read_text().splitlines()
    assert not any("check_gate.py" in call for call in calls)


def test_queue_fails_when_rollup_gate_fails_even_if_evals_succeed(tmp_path: Path):
    """The suite gate (build_rollup.py's exit code) must fail the queue even
    when every per-stem eval itself completed without error."""
    queue, env = _prepare_queue(tmp_path)
    env["FAKE_EVAL_RC"] = "0"
    env["FAKE_ROLLUP_RC"] = "1"

    result = subprocess.run(
        [str(queue), "alpha"],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode != 0
    assert "suite gate failed" in result.stderr
    calls = Path(env["UV_CALL_LOG"]).read_text().splitlines()
    assert any(call.endswith("scripts/build_rollup.py alpha") for call in calls)


def test_queue_passes_selected_stems_to_rollup(tmp_path: Path):
    queue, env = _prepare_queue(tmp_path)

    result = subprocess.run(
        [str(queue), "alpha"],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode == 0
    calls = Path(env["UV_CALL_LOG"]).read_text().splitlines()
    assert any(call.endswith("scripts/build_rollup.py alpha") for call in calls)


def test_queue_runs_stems_in_parallel_with_bounded_workers(tmp_path: Path):
    queue, env = _prepare_queue(tmp_path)
    env["TARS_EVAL_WORKERS"] = "2"
    env["FAKE_STEMS"] = "alpha\nbeta\n"
    env["FAKE_EVAL_SLEEP"] = "0.4"
    package_root = queue.parent.parent
    (package_root / "datasets" / "beta.yaml").write_text("items: []\n")

    # Rewrite fake uv so evals sleep and record start/end timestamps.
    fake_uv = Path(env["PATH"].split(os.pathsep)[0]) / "uv"
    fake_uv.write_text(
        """#!/usr/bin/env bash
printf '%s\\n' "$*" >>"$UV_CALL_LOG"
case "$*" in
  *list_dataset_stems.py*)
    printf '%b' "${FAKE_STEMS:-alpha\\n}"
    ;;
  *run_single_dataset_eval.py*)
    stem="${*: -1}"
    started="$(python3 -c 'import time; print(time.time())')"
    printf '%s start %s\\n' "$started" "$stem" >>"$UV_TIMING_LOG"
    sleep "${FAKE_EVAL_SLEEP:-0}"
    ended="$(python3 -c 'import time; print(time.time())')"
    printf '%s end %s\\n' "$ended" "$stem" >>"$UV_TIMING_LOG"
    exit "${FAKE_EVAL_RC:-0}"
    ;;
  *build_rollup.py*)
    exit "${FAKE_ROLLUP_RC:-0}"
    ;;
esac
"""
    )
    fake_uv.chmod(0o755)
    env["UV_TIMING_LOG"] = str(tmp_path / "timing.log")

    started = __import__("time").time()
    result = subprocess.run(
        [str(queue)],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    elapsed = __import__("time").time() - started

    assert result.returncode == 0, result.stderr
    # Serial would take ~0.8s of sleep alone; allow process/startup overhead.
    assert elapsed < 1.35
    timing = Path(env["UV_TIMING_LOG"]).read_text().splitlines()
    starts = [line for line in timing if " start " in line]
    assert len(starts) == 2
    start_times = sorted(float(line.split()[0]) for line in starts)
    # Both workers should begin within one sleep window of each other.
    assert start_times[1] - start_times[0] < 0.35


def test_queue_workers_default_is_bounded(tmp_path: Path):
    """Default workers > 1 so CI suite is parallel, but still capped."""
    queue, env = _prepare_queue(tmp_path)
    # Inspect the script source for the documented default rather than running
    # many stems — keeps the unit test offline and fast.
    source = queue.read_text(encoding="utf-8")
    assert 'TARS_EVAL_WORKERS:-2' in source or 'TARS_EVAL_WORKERS:-"2"' in source
    assert "TARS_EVAL_WORKERS" in source
