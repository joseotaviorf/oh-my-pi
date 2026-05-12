#!/usr/bin/env python3
"""
Script to run core model tests with coverage and check coverage threshold.

This script:
1. Runs pytest with coverage for core model tests (single execution)
2. Measures coverage of dags/core/ and packages/bietlejuice-runtime/src/bietlejuice/base/core_models/
3. Checks if coverage meets threshold (default: 80%, configurable)
4. Exits with error code if tests fail or coverage threshold not met

Execution model after the multi-package restructure:
- This script is launched from the compiler venv (Makefile uses
  `uv run --project packages/bietlejuice-compiler python ...check_core_model_coverage.py`),
  but `bietlejuice.base.core_models` lives under `packages/bietlejuice-runtime/`, which is
  NOT a dependency of `bietlejuice-compiler`. Running pytest with `sys.executable` would
  therefore fail to import the source under coverage.
- Solution: spawn pytest via `uv run --project packages/bietlejuice-runtime` so the
  runtime venv (which does have `bietlejuice.base.core_models`, `pyspark`, `delta-spark`,
  and `pytest-cov`) drives the test run. We deliberately do NOT pass `--no-sync` because
  CI runs from a bare `python:3.12-bookworm` image with no pre-existing runtime venv;
  uv must materialize one on first invocation. We keep `cwd=REPO_ROOT` so `dags/core/`
  and the runtime test paths resolve from the repo root, matching how
  `_find_project_root()` in the test files walks up to put the repo root on `sys.path`.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import List, Tuple


REPO_ROOT = Path(__file__).resolve().parents[5]
RUNTIME_PROJECT = REPO_ROOT / "packages" / "bietlejuice-runtime" / "envs" / "dbr-16-4"


# Core model source paths to measure coverage for (directory paths relative to
# REPO_ROOT).  We use directory paths instead of Python module names because
# `bietlejuice` is now a namespace package spanning multiple sub-projects;
# pytest-cov cannot correctly resolve a submodule within a namespace package and
# would fall back to measuring the entire namespace, inflating the denominator.
CORE_MODEL_SOURCE_PATHS = [
    "dags/core",
    "packages/bietlejuice-runtime/src/bietlejuice/base/core_models",
]

# Test paths - both core model DAG tests and helper unit tests now live under the
# runtime package.
TEST_PATHS = [
    "packages/bietlejuice-runtime/test/core_model_dags/",
    "packages/bietlejuice-runtime/test/unit/base/core_models/helpers/",
]

# Default coverage threshold
DEFAULT_THRESHOLD = 80.0


def _runtime_pytest_cmd(extra_args: List[str]) -> List[str]:
    """Build a `uv run` command that drives pytest from the runtime project venv.

    Note: `--no-sync` is intentionally NOT passed. CI runs this from a bare
    `python:3.12-bookworm` image with no pre-existing runtime venv, so uv must
    materialize one (installing pyspark, delta-spark, etc.) before pytest can
    collect tests. Subsequent invocations within the same process are no-ops
    once the venv is hydrated.
    """
    return [
        "uv",
        "run",
        "--project",
        str(RUNTIME_PROJECT),
        "python",
        "-m",
        "pytest",
        *extra_args,
    ]


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Check test coverage for core model source code"
    )
    parser.add_argument(
        "-t",
        "--threshold",
        type=float,
        default=None,
        help="Coverage threshold percentage (default: 80%% or COVERAGE_THRESHOLD env var)",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Output more detailed messages",
    )
    args = parser.parse_args()
    return args


def get_threshold(args) -> float:
    """Get coverage threshold from args, env var, or default."""
    if args.threshold is not None:
        return args.threshold
    env_threshold = os.environ.get("COVERAGE_THRESHOLD")
    if env_threshold:
        try:
            return float(env_threshold)
        except ValueError:
            print(f"Warning: Invalid COVERAGE_THRESHOLD value '{env_threshold}', using default {DEFAULT_THRESHOLD}%")
            return DEFAULT_THRESHOLD
    return DEFAULT_THRESHOLD


def check_pytest_cov_available() -> bool:
    """Check if pytest-cov plugin is available in the runtime venv."""
    try:
        result = subprocess.run(
            _runtime_pytest_cmd(["--help"]),
            capture_output=True,
            text=True,
            timeout=30,
            cwd=REPO_ROOT,
        )
        return "--cov" in result.stdout
    except (subprocess.TimeoutExpired, subprocess.SubprocessError, FileNotFoundError):
        return False


def build_coverage_sources() -> list:
    """Build the --cov argument list for pytest-cov using directory paths."""
    return [str(REPO_ROOT / p) for p in CORE_MODEL_SOURCE_PATHS]


def run_coverage_check(threshold: float, verbose: bool) -> Tuple[int, str]:
    """
    Run pytest with coverage and check if threshold is met.

    Returns:
        Tuple of (exit_code, coverage_output)
    """
    # Check if pytest-cov is available
    if not check_pytest_cov_available():
        error_msg = (
            "Error: pytest-cov plugin is not available.\n"
            "Please install it with: pip install pytest-cov\n"
            "Or run: make requirements-test"
        )
        print(error_msg)
        return 1, error_msg

    coverage_sources = build_coverage_sources()
    if not coverage_sources:
        print("Error: No valid core model source paths found for coverage measurement")
        return 1, ""

    # Create temporary file for JSON coverage report
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json_report_path = f.name

    try:
        # Build pytest args: each --cov needs its own flag.
        pytest_args: List[str] = ["-W", "ignore::DeprecationWarning"]
        for source in coverage_sources:
            pytest_args.extend(["--cov", source])
        pytest_args.extend([
            "--cov-report=term-missing",
            "--cov-report=term",  # Show all files, including those with 100% coverage
            f"--cov-report=json:{json_report_path}",
        ])
        pytest_args.extend(TEST_PATHS)

        cmd = _runtime_pytest_cmd(pytest_args)

        if verbose:
            print(f"Running coverage check with command: {' '.join(cmd)}")
            print(f"Working directory: {REPO_ROOT}")
            print(f"Coverage threshold: {threshold}%")
            print(f"Coverage sources: {', '.join(coverage_sources)}")
            print("")

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd=REPO_ROOT,
        )
        output = result.stdout + result.stderr

        if verbose:
            print(output)

        # Check if pytest ran successfully
        if result.returncode != 0:
            print(f"❌ Tests failed: pytest exited with code {result.returncode}")
            print("")
            print("Test failures must be fixed before coverage can be checked.")
            print("")
            if not verbose:
                print("Test output:")
                print(output)
            # Clean up temp file
            try:
                os.unlink(json_report_path)
            except OSError:
                pass
            return 1, output

        # Parse coverage percentage from JSON report
        coverage_percent = None
        try:
            # Check if JSON file exists and has content
            if not os.path.exists(json_report_path):
                if verbose:
                    print(f"Warning: JSON coverage report file not found: {json_report_path}")
            else:
                with open(json_report_path, 'r') as f:
                    content = f.read().strip()
                    if not content:
                        if verbose:
                            print("Warning: JSON coverage report file is empty")
                    else:
                        coverage_data = json.loads(content)
                        # Get total coverage percentage
                        coverage_percent = coverage_data.get('totals', {}).get('percent_covered', None)
        except (FileNotFoundError, json.JSONDecodeError, KeyError) as e:
            if verbose:
                print(f"Warning: Could not read JSON coverage report: {e}")

        # Fallback to parsing text output if JSON parsing failed
        if coverage_percent is None:
            for line in output.split("\n"):
                if "TOTAL" in line and "%" in line:
                    # Extract percentage from line like "TOTAL                   123    45    63%"
                    parts = line.split()
                    for part in parts:
                        if part.endswith("%"):
                            try:
                                coverage_percent = float(part.rstrip("%"))
                                break
                            except ValueError:
                                continue
                    if coverage_percent is not None:
                        break

        # Clean up temp file
        try:
            os.unlink(json_report_path)
        except OSError:
            pass

        if coverage_percent is None:
            print("Error: Could not parse coverage percentage from pytest output")
            print("")
            print("This usually means:")
            print("  1. Tests failed before coverage could be measured")
            print("  2. pytest-cov plugin is not installed or not recognized")
            print("  3. Coverage report was not generated")
            print("")
            print("Please ensure:")
            print("  - pytest-cov is installed: pip install pytest-cov")
            print("  - Tests can run successfully")
            print("")
            if verbose:
                print("Full output:")
                print(output)
            else:
                print("Run with -v flag for detailed output")
            return 1, output

        # Check threshold
        if coverage_percent < threshold:
            print(f"❌ Coverage check failed: {coverage_percent:.2f}% < {threshold:.2f}%")
            return 1, output
        else:
            print(f"✅ Coverage check passed: {coverage_percent:.2f}% >= {threshold:.2f}%")
            return 0, output

    except Exception as e:
        print(f"Unexpected error: {e}")
        # Clean up temp file on error
        try:
            os.unlink(json_report_path)
        except OSError:
            pass
        return 1, str(e)


def main():
    """Main entry point."""
    args = parse_args()
    threshold = get_threshold(args)

    print("")
    print("Core Model Test Coverage Check")
    print("=" * 40)
    print(f"Coverage threshold: {threshold}%")
    print(f"Test paths: {', '.join(TEST_PATHS)}")
    print(f"Source paths: {', '.join(CORE_MODEL_SOURCE_PATHS)}")
    print("")

    exit_code, output = run_coverage_check(threshold, args.verbose)

    if exit_code != 0:
        print("")
        print("Coverage report:")
        print(output)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
