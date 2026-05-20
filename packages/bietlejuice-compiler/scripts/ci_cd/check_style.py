#!/usr/bin/env python3
"""
Ruff style-check driver for bi-etl-ejuice.

Subcommands (invoked by make, not directly by developers):

  full          ruff format --check on package src/test trees + ruff check . (developer default)
  ci            diff-scoped check: format --check limited to package trees unless
                RUFF_CI_FULL_STRICT=1; ruff check on changed *.py (or . if strict)
  local-check   diff-scoped check: format --check on all changed *.py;
                ruff check on changed files (RUFF_LOCAL_FULL_LINT=1 → repo-wide)
  local-format  ruff format (write) on all changed *.py in diff

Diff anchor resolution (highest priority first):
  RUFF_DIFF_REF  → RUFF_CI_DIFF / RUFF_LOCAL_DIFF  → built-in default per subcommand

Env flags:
  RUFF_CI_FULL_STRICT    set to 1 to enforce format + ruff check on all changed files
  RUFF_LOCAL_FULL_LINT   set to 1 to run ruff check . instead of scoped check
  RUFF_CI_DIFF           override diff ref for ci subcommand (default: origin/master...HEAD)
  RUFF_LOCAL_DIFF        override diff ref for local-* subcommands (default: HEAD)

Usage (via Makefile — preferred):
  make check-style
  make check-style-local
  make lint-local

Direct invocation (CI containers; requires ruff on PATH via uv run):
  uv run --project packages/bietlejuice-compiler \\
      python packages/bietlejuice-compiler/scripts/ci_cd/check_style.py ci
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

# Package trees eligible for format --check in non-strict CI mode.
# Mirrors RUFF_FORMAT_PATHS in the Makefile.
_PACKAGE_ROOTS: list[str] = [
    "packages/bietlejuice-core/src",
    "packages/bietlejuice-core/test",
    "packages/bietlejuice-airflow/src",
    "packages/bietlejuice-airflow/test",
    "packages/bietlejuice-runtime/src",
    "packages/bietlejuice-runtime/test",
    "packages/bietlejuice-compiler/src",
    "packages/bietlejuice-compiler/test",
    "packages/emr-cli/src",
    "packages/emr-cli/test",
]

# Regex pattern (used via grep) matching package-tree paths eligible for CI format --check.
_PACKAGE_PATH_PATTERN = (
    r"^packages/bietlejuice-(core|airflow|runtime|compiler)/(src|test)/"
    r"|^packages/emr-cli/(src|test)/"
)


def _git_changed_py(ref: str) -> list[str]:
    """Return existing *.py files changed in the given git diff ref."""
    result = subprocess.run(
        ["git", "diff", ref, "--name-only", "--diff-filter=d"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return []
    return [
        f
        for f in result.stdout.splitlines()
        if f.endswith(".py") and Path(f).is_file()
    ]


def _filter_package_paths(files: list[str]) -> list[str]:
    """Keep only files under package src/test trees (CI non-strict format scope)."""
    import re

    pattern = re.compile(_PACKAGE_PATH_PATTERN)
    return [f for f in files if pattern.match(f)]


def _ruff(*args: str) -> int:
    """Run ruff with the given arguments; return the exit code."""
    sys.stdout.flush()
    result = subprocess.run(["ruff", *args], check=False)
    return result.returncode


def _count(files: list[str]) -> int:
    return len(files)


# ---------------------------------------------------------------------------
# Subcommand handlers
# ---------------------------------------------------------------------------


def cmd_full() -> int:
    """Developer default: format --check on fixed package paths + ruff check ."""
    print()
    print("Running Check Style")
    print("==========")
    print()
    rc = _ruff("format", "--check", *_PACKAGE_ROOTS)
    if rc != 0:
        return rc
    return _ruff("check", ".")


def cmd_ci(diff_ref: str | None) -> int:
    """CI/Woodpecker diff-scoped check."""
    ref = diff_ref or os.environ.get("RUFF_CI_DIFF", "origin/master...HEAD")
    strict = os.environ.get("RUFF_CI_FULL_STRICT", "")

    print()
    print("Running Check Style (CI)")
    print("==========")
    print()

    existing = _git_changed_py(ref)

    if strict:
        # Strict: format --check all changed *.py + repo-wide ruff check
        if existing:
            print(f"Ruff format --check on {_count(existing)} Python file(s)")
            rc = _ruff("format", "--check", *existing)
            if rc != 0:
                return rc
        else:
            print(f"No changed Python files in diff {ref} — skipping ruff format --check")

        print("Ruff check (repo-wide)")
        return _ruff("check", ".")

    # Default: format --check only package-tree files; ruff check on changed files
    fmt_files = _filter_package_paths(existing)
    if fmt_files:
        print(f"Ruff format --check on {_count(fmt_files)} Python file(s)")
        rc = _ruff("format", "--check", *fmt_files)
        if rc != 0:
            return rc
    elif existing:
        print(
            f"Skipping ruff format --check for non-package paths "
            f"({_count(existing)} file(s)); set RUFF_CI_FULL_STRICT=1 to enforce on all"
        )

    if existing:
        print(f"Ruff check on {_count(existing)} changed Python file(s)")
        return _ruff("check", *existing)

    print(f"No changed Python files in diff {ref} — skipping ruff check")
    return 0


def cmd_local_check(diff_ref: str | None) -> int:
    """Local diff-scoped check: format --check all changed .py; ruff check on changed files."""
    ref = diff_ref or os.environ.get("RUFF_LOCAL_DIFF", "HEAD")
    full_lint = os.environ.get("RUFF_LOCAL_FULL_LINT", "")

    print()
    print("Running Check Style (local — scoped to changed Python files)")
    print("==========")
    print()

    existing = _git_changed_py(ref)

    if existing:
        print(f"Ruff format --check on {_count(existing)} file(s); diff anchor: {ref}")
        rc = _ruff("format", "--check", *existing)
        if rc != 0:
            return rc
    else:
        print(f"No changed Python files in diff {ref}; skipping format check")

    if full_lint:
        print(f"Ruff check on whole repo (RUFF_LOCAL_FULL_LINT={full_lint})")
        return _ruff("check", ".")
    if existing:
        print("Ruff check on changed file(s) only (use RUFF_LOCAL_FULL_LINT=1 for repo-wide)")
        return _ruff("check", *existing)

    print("No changed Python files; skipping ruff check")
    return 0


def cmd_local_format(diff_ref: str | None) -> int:
    """Apply ruff format (write) to all changed *.py in diff."""
    ref = diff_ref or os.environ.get("RUFF_LOCAL_DIFF", "HEAD")

    print()
    print("Running Lint Local (ruff format on changed Python files)")
    print("==========")
    print()

    existing = _git_changed_py(ref)

    if existing:
        print(f"Ruff format on {_count(existing)} file(s); diff anchor: {ref}")
        return _ruff("format", *existing)

    print(f"No changed Python files in diff {ref}; nothing to format")
    return 0


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

_MODES = {
    "full": cmd_full,
    "ci": cmd_ci,
    "local-check": cmd_local_check,
    "local-format": cmd_local_format,
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "mode",
        choices=list(_MODES),
        help="Check mode: full (developer), ci (Woodpecker), local-check, local-format",
    )
    parser.add_argument(
        "--diff-ref",
        default=None,
        help="Override the git diff reference (highest-priority; env vars apply when omitted)",
    )
    args = parser.parse_args()

    if args.mode == "full":
        rc = cmd_full()
    else:
        rc = _MODES[args.mode](args.diff_ref)

    sys.exit(rc)


if __name__ == "__main__":
    main()
