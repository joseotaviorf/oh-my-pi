#!/usr/bin/env python3
"""
Maps changed Python source files to their corresponding unit test directories.

Outputs a newline-separated list of existing pytest paths based on the diff
against BASE_BRANCH (default: origin/master). Falls back to tests/unit/ when
changes span framework code that affects the full suite.

Usage:
    python scripts/ci_cd/detect_changed_tests.py [base_branch]

Examples:
    python scripts/ci_cd/detect_changed_tests.py
    python scripts/ci_cd/detect_changed_tests.py origin/forno
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

UNIT_TESTS_ROOT = Path("tests/unit")
FULL_SUITE_PATH = f"{UNIT_TESTS_ROOT}/"

_BIETLEJUICE_TOP = re.compile(r"^bietlejuice/([^/]+)/")


def _git_ok(args: list[str]) -> bool:
    result = subprocess.run(
        ["git", *args],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode == 0


def _git_lines(args: list[str]) -> list[str]:
    result = subprocess.run(
        ["git", *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return []
    return [line for line in result.stdout.splitlines() if line.strip()]


def get_changed_python_files(base_branch: str) -> list[str]:
    """Collect changed Python files between the current branch and base (or HEAD~1 fallback)."""
    if _git_ok(["rev-parse", "--verify", base_branch]):
        return _git_lines(
            ["diff", "--name-only", f"{base_branch}...HEAD", "--", "*.py"]
        )
    return _git_lines(["diff", "--name-only", "HEAD~1", "--", "*.py"])


def resolve_test_paths(changed_files: list[str]) -> tuple[bool, set[str]]:
    """
    Map changed files to pytest directory scopes.

    Returns:
        needs_full_suite: True if the entire unit tree should run.
        selected_paths: Directory paths with trailing slash (pytest scopes), non-empty when not full.
    """
    selected_paths: set[str] = set()
    needs_full_suite = False

    for file in changed_files:
        if needs_full_suite:
            break

        match = _BIETLEJUICE_TOP.match(file)
        if match:
            top_module = match.group(1)
            candidate = UNIT_TESTS_ROOT / top_module
            if candidate.is_dir():
                selected_paths.add(f"{candidate}/")
            else:
                needs_full_suite = True
            continue

        tests_unit_prefix = f"{UNIT_TESTS_ROOT}/"
        if file.startswith(tests_unit_prefix):
            subpath = file[len(tests_unit_prefix) :].lstrip("/")
            if not subpath:
                continue
            top_dir = subpath.split("/", 1)[0]
            candidate = UNIT_TESTS_ROOT / top_dir
            if candidate.is_dir():
                selected_paths.add(f"{candidate}/")
            else:
                selected_paths.add(f"{UNIT_TESTS_ROOT}/{subpath}")
            continue

        if file.startswith("scripts/") or file == "setup.py" or file == "conftest.py":
            needs_full_suite = True
            continue

        # DAG wrappers and anything else uncategorised → full suite (same as bash).
        needs_full_suite = True

    return needs_full_suite, selected_paths


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Print newline-separated pytest paths for unit tests affected by "
            "Python files changed since the merge base with the given branch."
        ),
    )
    parser.add_argument(
        "base_branch",
        nargs="?",
        default="origin/master",
        help="Git ref to diff against (default: %(default)s)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    changed = get_changed_python_files(args.base_branch)
    if not changed:
        return 0

    needs_full, selected = resolve_test_paths(changed)
    if needs_full or not selected:
        print(FULL_SUITE_PATH)
    else:
        for path in sorted(selected):
            print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
