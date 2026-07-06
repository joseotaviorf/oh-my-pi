#!/usr/bin/env python3
"""Run core-model tests (scoped to the impacted model when possible) and gate on
DIFF coverage: the fraction of lines changed in this branch that the tests cover.

Execution model (unchanged from the pooled-coverage version):
- Launched from the compiler venv, but ``bietlejuice.base.core_models`` lives under
  ``packages/bietlejuice-runtime/``. We therefore spawn pytest via
  ``uv run --project packages/bietlejuice-runtime/envs/dbr-16-4`` (the DBR env that
  has the source, pyspark, delta-spark, pytest-cov, and now diff-cover) with
  ``cwd=REPO_ROOT``. ``UV_PROJECT_ENVIRONMENT`` is overridden to the baked DBR 16.4
  venv when present (CI/devcontainer), mirroring the Makefile's ``DBR_UV_ENV``.

Two behavior changes vs. the old pooled-coverage version:
1. Scope: tests + coverage sources come from ``resolve_scope(...)``. A per-model
   change runs only that model's tests; shared/base changes fall back to the full
   suite (see ``core_model_scope``).
2. Gate: the pass/fail authority is ``diff-cover`` over the changed lines, not a
   pooled aggregate percentage. This judges only the code the PR added/changed, so
   touching a historically under-covered model no longer fails for unrelated
   reasons, while newly added untested lines are correctly flagged. Enforced
   always (no report-only toggle).

Coverage config: a committed ``coverage.cfg`` (next to this script) is passed via
``--cov-config`` so ``exclude_lines`` (entrypoint ``if __name__`` blocks, pragmas)
and ``relative_files`` apply even though the step runs from the repo root and does
not pick up the runtime pyproject's ``[tool.coverage.*]``.
"""

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import List, Tuple

from core_model_scope import REPO_ROOT, resolve_scope

from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref

RUNTIME_PROJECT = REPO_ROOT / "packages" / "bietlejuice-runtime" / "envs" / "dbr-16-4"

# Committed coverage config used only by this step (exclude_lines + relative_files).
COVERAGE_CONFIG = Path(__file__).resolve().parent / "coverage.cfg"

# CI/devcontainer images bake the DBR 16.4 venv here and export a global
# UV_PROJECT_ENVIRONMENT pointing at the workspace venv. Override it so the spawned
# pytest/diff-cover run in the DBR 16.4 venv (which carries pytest-cov + diff-cover).
BAKED_DBR_VENV = Path("/opt/bietlejuice/venvs/dbr-16-4")

DEFAULT_THRESHOLD = 80.0

# pytest exit code 5 = "no tests collected". A scoped model dir that exists but
# has no tests must not be read as a failure.
PYTEST_NO_TESTS_COLLECTED = 5


def _runtime_env() -> dict:
    """Environment for spawned subprocesses (mirrors the Makefile's DBR_UV_ENV)."""
    env = os.environ.copy()
    if (BAKED_DBR_VENV / "bin" / "python3").exists():
        env["UV_PROJECT_ENVIRONMENT"] = str(BAKED_DBR_VENV)
    return env


def _uv_run(tool_args: List[str]) -> List[str]:
    """Build ``uv run --project <dbr env> <tool_args...>``."""
    return ["uv", "run", "--project", str(RUNTIME_PROJECT), *tool_args]


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run scoped core-model tests and gate on diff coverage"
    )
    parser.add_argument(
        "-t",
        "--threshold",
        type=float,
        default=None,
        help="Diff-coverage threshold %% (default: 80 or COVERAGE_THRESHOLD env var)",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Output more detailed messages",
    )
    return parser.parse_args()


def get_threshold(args) -> float:
    """Get diff-coverage threshold from args, env var, or default."""
    if args.threshold is not None:
        return args.threshold
    env_threshold = os.environ.get("COVERAGE_THRESHOLD")
    if env_threshold:
        try:
            return float(env_threshold)
        except ValueError:
            print(
                f"Warning: invalid COVERAGE_THRESHOLD '{env_threshold}', "
                f"using default {DEFAULT_THRESHOLD}%"
            )
    return DEFAULT_THRESHOLD


def _tool_available(tool_args: List[str], needle: str) -> bool:
    try:
        result = subprocess.run(
            _uv_run(tool_args),
            capture_output=True,
            text=True,
            timeout=120,
            cwd=REPO_ROOT,
            env=_runtime_env(),
        )
        return needle in (result.stdout + result.stderr)
    except (subprocess.TimeoutExpired, subprocess.SubprocessError, FileNotFoundError):
        return False


def check_pytest_cov_available() -> bool:
    return _tool_available(["python", "-m", "pytest", "--help"], "--cov")


def check_diff_cover_available() -> bool:
    return _tool_available(["diff-cover", "--version"], "diff-cover")


def run_scoped_tests(scope, xml_path: str, verbose: bool) -> Tuple[int, str]:
    """Run pytest for the scoped test paths, writing a Cobertura XML report."""
    pytest_args: List[str] = [
        "-W",
        "ignore::DeprecationWarning",
        f"--cov-config={COVERAGE_CONFIG}",
    ]
    # Relative source paths (cwd=REPO_ROOT) so XML filenames match git paths.
    for source in scope.cov_sources:
        pytest_args.extend(["--cov", source])
    pytest_args.extend(
        [
            "--cov-report=term-missing",
            f"--cov-report=xml:{xml_path}",
        ]
    )
    pytest_args.extend(scope.test_paths)

    cmd = _uv_run(["python", "-m", "pytest", *pytest_args])
    if verbose:
        print(f"Running: {' '.join(cmd)}")
        print(f"Working directory: {REPO_ROOT}")
        print("")

    result = subprocess.run(
        cmd, capture_output=True, text=True, cwd=REPO_ROOT, env=_runtime_env()
    )
    output = result.stdout + result.stderr
    if verbose:
        print(output)
    return result.returncode, output


def run_diff_cover(xml_path: str, base_ref: str, threshold: float) -> Tuple[int, str]:
    """Gate on the coverage of changed lines. Returns (exit_code, output)."""
    dc_args = [
        "diff-cover",
        xml_path,
        "--compare-branch",
        base_ref,
        "--diff-range-notation",
        "...",
        "--fail-under",
        f"{threshold:g}",
    ]
    result = subprocess.run(
        _uv_run(dc_args),
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
        env=_runtime_env(),
    )
    output = result.stdout + result.stderr
    print(output)
    return result.returncode, output


def main():
    args = parse_args()
    threshold = get_threshold(args)
    branch = os.environ.get("CI_COMMIT_BRANCH", "")

    print("")
    print("Core Model Test Coverage Check (scoped tests + diff coverage)")
    print("=" * 60)

    scope = resolve_scope(branch)
    if scope.run_full:
        print(f"Scope:       FULL SUITE ({scope.fallback_reason})")
    else:
        print(f"Scope:       models -> {', '.join(scope.models)}")
    print(f"Test paths:  {', '.join(scope.test_paths)}")
    print(f"Cov sources: {', '.join(scope.cov_sources)}")
    print(f"Diff base:   {resolve_diff_from_ref(branch)}")
    print(f"Threshold:   {threshold}% on changed lines (enforced)")
    print("")

    if not check_pytest_cov_available():
        print("Error: pytest-cov is not available in the DBR 16.4 env.")
        print("Run: uv sync --directory packages/bietlejuice-runtime/envs/dbr-16-4")
        sys.exit(1)
    if not check_diff_cover_available():
        print("Error: diff-cover is not available in the DBR 16.4 env.")
        print(
            "Add 'diff-cover' to packages/bietlejuice-runtime/envs/dbr-16-4 dev deps."
        )
        sys.exit(1)

    with tempfile.NamedTemporaryFile(mode="w", suffix=".xml", delete=False) as f:
        xml_path = f.name

    try:
        rc, output = run_scoped_tests(scope, xml_path, args.verbose)

        if rc == PYTEST_NO_TESTS_COLLECTED:
            print(
                "ℹ️  No tests collected for the scoped paths - nothing to gate. Passing."
            )
            sys.exit(0)

        if rc != 0:
            print(f"❌ Tests failed: pytest exited with code {rc}")
            if not args.verbose:
                print(output)
            sys.exit(1)

        base_ref = resolve_diff_from_ref(branch)
        dc_rc, _ = run_diff_cover(xml_path, base_ref, threshold)

        if dc_rc != 0:
            print(f"❌ Diff coverage below {threshold:.2f}% on changed lines.")
            sys.exit(1)

        print(f"✅ Diff coverage check passed (>= {threshold:.2f}% on changed lines).")
        sys.exit(0)
    finally:
        try:
            os.unlink(xml_path)
        except OSError:
            pass


if __name__ == "__main__":
    main()
