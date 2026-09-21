#!/usr/bin/env python3
"""CI gate: block DAG metadata changes that break llm_context golden queries.

When a DAG ``metadata/**/*.yml`` file changes, checks whether the affected table is
referenced in any golden query under ``docs/llm_context/{business,metric}_entities/``.
Removing or renaming a column that a golden query still uses is a blocking error;
adding columns on a referenced table emits a non-blocking warning.

SQL-only changes are out of scope here — column contracts live in metadata YAML and
SQL↔metadata consistency is covered by existing governance validators.

Usage:
    python validate_llm_context_dag_impact.py --changed-only -b "$CI_COMMIT_BRANCH"
    python validate_llm_context_dag_impact.py --paths dags/rent/dw_rent/metadata/dw/fact_visits.yml

Exit codes: 0 = pass (warnings allowed); 1 = blocking error or bad invocation.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from bietlejuice.ci.ci_diff_ref import fetch_diff_base, resolve_diff_from_ref

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from llm_context_dag_impact_validator import (  # noqa: E402
    build_golden_query_index,
    collect_table_impacts,
    filter_dag_impact_paths,
    validate_table_impacts,
)

_REPO_ROOT = _SCRIPT_DIR.parents[2]


def _git_changed_dag_paths(branch: str) -> list[str]:
    from_ref = resolve_diff_from_ref(branch)
    fetch_diff_base(from_ref)
    cmd = ["git", "diff", "--name-only", "--diff-filter=ACDMR", f"{from_ref}...HEAD"]
    result = subprocess.run(
        cmd, capture_output=True, text=True, check=True, cwd=_REPO_ROOT
    )
    return filter_dag_impact_paths(
        line.strip() for line in result.stdout.splitlines() if line.strip()
    )


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate DAG metadata YAML changes against llm_context golden queries."
        )
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--changed-only",
        action="store_true",
        help="Validate only DAG metadata YAML files changed vs the diff base (CI).",
    )
    group.add_argument(
        "--paths",
        nargs="+",
        type=Path,
        help="Explicit DAG metadata YAML paths to validate (local testing).",
    )
    parser.add_argument(
        "-b",
        "--branch",
        default=os.environ.get("CI_COMMIT_BRANCH", ""),
        help="Current branch (CI_COMMIT_BRANCH); used with --changed-only.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)

    if args.paths:
        changed = filter_dag_impact_paths(str(p) for p in args.paths)
        if not changed:
            print(
                "✗ none of the given --paths are DAG metadata YAML files under dags/",
                file=sys.stderr,
            )
            return 1
        from_ref = "HEAD"
        print(f"Scope           : {len(changed)} explicitly-listed DAG path(s)")
    else:
        from_ref = resolve_diff_from_ref(args.branch)
        print(
            f"Scope           : DAG metadata YAML changed vs {from_ref} "
            f"({from_ref}...HEAD — whole branch delta, not just the last commit)"
        )
        try:
            changed = _git_changed_dag_paths(args.branch)
        except subprocess.CalledProcessError as exc:
            print(f"✗ git diff failed: {exc}", file=sys.stderr)
            return 1
        if not changed:
            print("No changed DAG metadata YAML files detected — nothing to validate.")
            return 0

    for rel in changed:
        print(f"  • {rel}")

    impacts = collect_table_impacts(changed, from_ref)
    if not impacts:
        print(
            "No metadata column changes detected for changed tables — nothing to check."
        )
        return 0

    print(f"Column deltas     : {len(impacts)} table(s)")
    gq_index = build_golden_query_index()
    errors, warnings = validate_table_impacts(impacts, gq_index)

    for warning in warnings:
        print(f"  ⚠ {warning}")
    for error in errors:
        print(f"  ✗ {error}", file=sys.stderr)

    if warnings:
        print(f"\n{len(warnings)} warning(s) — non-blocking.")

    if errors:
        print(
            f"\n✗ {len(errors)} blocking issue(s): golden queries in docs/llm_context/ "
            "reference removed or renamed columns. Update the entity doc(s) or revert "
            "the metadata change.",
            file=sys.stderr,
        )
        return 1

    print("\n✓ No golden-query breakage detected for changed DAG tables.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
