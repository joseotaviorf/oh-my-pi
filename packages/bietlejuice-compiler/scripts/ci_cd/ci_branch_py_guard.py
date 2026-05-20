#!/usr/bin/env python3
"""
Guard for feature-branch push events in Woodpecker CI.

Problem: Woodpecker's when.path filter evaluates only the latest commit on a
push, so a non-Python follow-up commit (e.g. YAML-only change) can skip a
step even though earlier commits in the branch changed Python files. To avoid
this, affected steps run unconditionally for feature branches and call this
script as an early-exit guard: it checks the full branch diff vs master and
signals "skip" when there are no .py changes.

Exit codes:
  0  — has .py changes in the full branch diff, or the event is not a
       feature-branch push; the caller should continue to the next command.
  1  — no .py changes detected; the caller should treat the step as done.
       Wire the calling step with `|| exit 0` so Woodpecker sees success:
         uv run ... python ci_branch_py_guard.py <label> || exit 0

On events other than a feature-branch push the script is a no-op (exit 0),
so it is safe to include unconditionally in any step.

Usage (in a Woodpecker step — inside a single `|` block so `exit 0` propagates):
  - |
    uv run --project packages/bietlejuice-compiler \\
        python packages/bietlejuice-compiler/scripts/ci_cd/ci_branch_py_guard.py \\
        files-validation || exit 0
    make files-validation

Arguments:
  label   Short label shown in the skip log line, e.g. "lint" or
          "files-validation" (default: "step").
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys


_PROTECTED_BRANCHES = {"master", "forno"}


def _is_hotfix(branch: str) -> bool:
    return branch.startswith("hotfix/")


def _has_py_changes_in_branch() -> bool:
    """Return True when the full branch diff vs origin/master contains *.py files."""
    result = subprocess.run(
        ["git", "diff", "origin/master...HEAD", "--name-only"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        # git diff failed (e.g. origin/master not fetched yet); treat as no changes
        # to avoid blocking CI unexpectedly.
        return False
    return any(line.endswith(".py") for line in result.stdout.splitlines() if line.strip())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "label",
        nargs="?",
        default="step",
        help="Step name shown in the skip message (default: 'step')",
    )
    args = parser.parse_args()

    event = os.environ.get("CI_PIPELINE_EVENT", "")
    branch = os.environ.get("CI_COMMIT_BRANCH", "")

    # Only intercept feature-branch push events.
    if event != "push" or branch in _PROTECTED_BRANCHES or _is_hotfix(branch):
        sys.exit(0)

    if not _has_py_changes_in_branch():
        print(f"No Python files in full branch diff vs master — {args.label} skipped")
        sys.exit(1)  # caller uses `|| exit 0` to skip gracefully

    sys.exit(0)


if __name__ == "__main__":
    main()
