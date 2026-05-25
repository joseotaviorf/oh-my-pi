#!/usr/bin/env python3
"""
Script to check if there are changes in core model related paths.

This script:
1. Uses git diff to identify changed files
2. Filters for files matching core model paths:
   - dags/core/**
   - packages/bietlejuice-runtime/test/core_model_dags/**
   - packages/bietlejuice-runtime/src/bietlejuice/base/core_models/**
3. Returns exit code 0 if no relevant changes, 1 if changes exist

NOTE: After the multi-package restructure, `bietlejuice/base/core_models/` and
`tests/core_model_dags/` no longer exist at the repo root. The canonical locations
are under `packages/bietlejuice-runtime/`. Path patterns below must stay in sync with
the `core-model-tests-and-coverage` step's `when.path` filter in `.woodpecker/tests.yml`.
"""

import argparse
import sys
from pathlib import Path
from typing import List, Tuple

# Import GitService for git-based change detection
sys.path.append(str(Path(__file__).parent.parent.parent))
from services.git_service import GitService

# Path patterns to check for changes (matched via str.startswith against git-diff paths)
CORE_MODEL_PATHS = [
    "dags/core/",
    "packages/bietlejuice-runtime/test/core_model_dags/",
    "packages/bietlejuice-runtime/test/unit/base/core_models/",
    "packages/bietlejuice-runtime/src/bietlejuice/base/core_models/",
    "packages/bietlejuice-airflow/src/bietlejuice/base/core_models/",
    "packages/bietlejuice-core/src/bietlejuice/base/core_models/",
]


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
    args = parser.parse_args()
    branch = args.branch
    all_files = args.all_files
    verbose = args.verbose
    mode = None
    if branch:
        mode = "branch"
    if all_files:
        mode = "all_files"
    return mode, (branch or all_files), verbose


def matches_core_model_path(file_path: str) -> bool:
    """
    Check if a file path matches any of the core model path patterns.

    Args:
        file_path: The file path to check

    Returns:
        True if the path matches any core model pattern, False otherwise
    """
    for pattern in CORE_MODEL_PATHS:
        if file_path.startswith(pattern):
            return True
    return False


def get_changed_files(mode, input) -> List[Tuple[str, str]]:
    """
    Get list of changed files based on mode.

    Returns:
        List of tuples (file_path, status)
    """
    files = []
    if mode == "all_files":
        # Always return that changes exist
        return [("all", "A")]
    elif mode == "branch":
        git_service = GitService()
        if input == "master":
            from_branch = "HEAD~1"
        else:
            from_branch = "origin/master"
            # Fetch master branch to ensure we have the latest changes
            git_service.fetch("master")

        # Get all changed files
        changed_files = git_service.get_modified_files_from_diff(from_branch, "HEAD")

        # Filter for files matching core model paths
        for file_path, status in changed_files.items():
            if status in GitService.UPSERT_STATUS_CODES:
                if matches_core_model_path(file_path):
                    files.append((file_path, status))

    return files


def check_core_model_changes(mode="all_files", input=None, verbose=False) -> bool:
    """
    Check if there are changes in core model related paths.

    Returns:
        True if changes exist, False otherwise
    """
    if mode == "all_files":
        if verbose:
            print("🔍 Checking all files mode - changes will be detected")
        return True
    elif mode == "branch":
        if verbose:
            print(f"🔍 Checking for core model changes in branch: {input}")

    # Get changed files
    changed_files = get_changed_files(mode, input)

    if not changed_files:
        if verbose:
            print("✅ No core model related changes detected")
        return False

    if verbose:
        print(f"📁 Found {len(changed_files)} changed file(s) in core model paths:")
        for file_path, status in changed_files:
            print(f"   - {file_path} ({status})")
    else:
        print(f"📁 Found {len(changed_files)} changed file(s) in core model paths")

    return True


def main():
    """Main entry point."""
    mode, input, verbose = parse_args()
    has_changes = check_core_model_changes(mode, input, verbose)

    if has_changes:
        print("✅ Core model changes detected - tests should run")
        sys.exit(1)  # Exit code 1 means changes found
    else:
        print("ℹ️  No core model changes detected - skipping tests")
        sys.exit(0)  # Exit code 0 means no changes


if __name__ == "__main__":
    main()
