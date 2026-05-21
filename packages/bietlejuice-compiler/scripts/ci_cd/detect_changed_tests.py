#!/usr/bin/env python3
"""
Detects which packages have test-relevant Python changes vs a base branch.

Outputs one package identifier per line (core, airflow, runtime, compiler,
emr-cli).
The Makefile unit-tests-changed target reads this and dispatches per-package
pytest invocations with --testmon.

Falls back to outputting ALL packages when changes span framework/root files
that could affect any package.

Usage:
    python detect_changed_tests.py [base_branch]

Examples:
    python detect_changed_tests.py
    python detect_changed_tests.py origin/forno
"""

from __future__ import annotations

import argparse
import subprocess
import sys

PACKAGES = ("core", "airflow", "runtime", "compiler", "emr-cli")

_PACKAGE_SRC_PREFIXES = {
    "packages/bietlejuice-core/": "core",
    "packages/bietlejuice-airflow/": "airflow",
    "packages/bietlejuice-runtime/": "runtime",
    "packages/bietlejuice-compiler/": "compiler",
    "packages/emr-cli/": "emr-cli",
}


def _git_ok(args: list[str]) -> bool:
    result = subprocess.run(
        ["git", *args], capture_output=True, text=True, check=False
    )
    return result.returncode == 0


def _git_lines(args: list[str]) -> list[str]:
    result = subprocess.run(
        ["git", *args], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        return []
    return [line for line in result.stdout.splitlines() if line.strip()]


def get_changed_python_files(base_branch: str) -> list[str]:
    """Collect changed Python files between the current branch and base."""
    if _git_ok(["rev-parse", "--verify", base_branch]):
        return _git_lines(
            ["diff", "--name-only", f"{base_branch}...HEAD", "--", "*.py"]
        )
    return _git_lines(["diff", "--name-only", "HEAD~1", "--", "*.py"])


def resolve_affected_packages(changed_files: list[str]) -> tuple[bool, set[str]]:
    """
    Map changed files to affected package identifiers.

    Returns:
        needs_all: True if all packages should be tested.
        affected: Set of package identifiers.
    """
    affected: set[str] = set()

    for filepath in changed_files:
        matched_pkg = None
        for prefix, pkg in _PACKAGE_SRC_PREFIXES.items():
            if filepath.startswith(prefix):
                matched_pkg = pkg
                break

        if matched_pkg:
            affected.add(matched_pkg)
            continue

        if filepath.startswith("dags/") and filepath.endswith(".py"):
            affected.add("runtime")
            continue

        # Root-level Python files (conftest.py, setup.py, scripts outside packages)
        # or anything unrecognised → test everything.
        return True, set(PACKAGES)

    return False, affected


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Print package identifiers affected by Python changes."
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

    needs_all, affected = resolve_affected_packages(changed)
    if needs_all:
        for pkg in PACKAGES:
            print(pkg)
    else:
        for pkg in sorted(affected):
            print(pkg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
