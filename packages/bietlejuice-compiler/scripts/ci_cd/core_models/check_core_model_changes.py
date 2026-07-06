#!/usr/bin/env python3
"""Check whether there are changes in core-model related paths.

Exit code 1 = changes found (tests should run); exit code 0 = no changes (skip).
Path classification is delegated to ``core_model_scope`` so it stays in sync with
``check_core_model_coverage.py``.

NOTE: After the multi-package restructure, ``bietlejuice/base/core_models/`` and
``tests/core_model_dags/`` no longer exist at the repo root. The canonical
locations are under ``packages/bietlejuice-runtime/``. The path patterns live in
``core_model_scope`` and must stay in sync with the ``&core_model_tests_path``
anchor on ``core-model-tests-and-coverage`` in ``.woodpecker/tests.yml``.
"""

import argparse
import sys

from core_model_scope import get_changed_core_model_files


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-v",
        "--verbose",
        help="Output more detailed messages",
        action="store_true",
        required=False,
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("-b", "--branch", help="Branch to be checked", required=False)
    group.add_argument(
        "-a",
        "--all-files",
        help="Check all files (always returns changes found)",
        action="store_true",
        required=False,
    )
    return parser.parse_args()


def main():
    """Main entry point."""
    args = parse_args()

    if args.all_files:
        if args.verbose:
            print("🔍 Checking all files mode - changes will be detected")
        print("✅ Core model changes detected - tests should run")
        sys.exit(1)

    if args.verbose:
        print(f"🔍 Checking for core model changes in branch: {args.branch}")

    changed = get_changed_core_model_files(args.branch)

    if not changed:
        if args.verbose:
            print("✅ No core model related changes detected")
        print("ℹ️  No core model changes detected - skipping tests")
        sys.exit(0)

    if args.verbose:
        print(f"📁 Found {len(changed)} changed file(s) in core model paths:")
        for path, status in changed:
            print(f"   - {path} ({status})")
    else:
        print(f"📁 Found {len(changed)} changed file(s) in core model paths")

    print("✅ Core model changes detected - tests should run")
    sys.exit(1)


if __name__ == "__main__":
    main()
