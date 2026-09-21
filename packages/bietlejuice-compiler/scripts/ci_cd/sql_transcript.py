"""
SQL Transpiler Script - Trino to Databricks

This script converts SQL files from Trino syntax to Databricks syntax using sqlglot.
It can be used as part of CI/CD to automatically transpile new or modified SQL files.

Usage:
    # Transpile all new/modified SQL files in a git diff
    python sql_transcript.py --mode git-diff --from-branch origin/master --to-branch HEAD

    # Transpile a specific SQL file
    python sql_transcript.py --mode single-file --file path/to/file.sql

    # Transpile all SQL files in a directory
    python sql_transcript.py --mode directory --directory dags/

    # Dry run (show changes without writing)
    python sql_transcript.py --mode git-diff --from-branch origin/master --to-branch HEAD --dry-run
"""

import argparse
import logging
import os
import re
import sys
from typing import List, Optional, Tuple

from sqlglot import transpile

# Add the project root to the path
BI_ETL_EJUICE_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
sys.path.append(BI_ETL_EJUICE_ROOT)

from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref
from scripts.services.git_service import GitService

logger = logging.getLogger(__name__)


class SQLTranspiler:
    """Handles SQL transpilation from Trino to Databricks syntax"""

    SOURCE_DIALECT = "trino"
    TARGET_DIALECT = "databricks"

    def __init__(self, dry_run: bool = False):
        """
        Initialize the SQL transpiler

        Args:
            dry_run: If True, only show what would be changed without writing files
        """
        self.dry_run = dry_run
        self.success_count = 0
        self.error_count = 0
        self.unchanged_count = 0
        self.errors: List[Tuple[str, str]] = []
        self.current_date_replacements = 0

    def apply_custom_replacements(self, sql_content: str) -> Tuple[str, int]:
        """
        Apply custom SQL replacements that are specific to the project

        Args:
            sql_content: The SQL content to apply replacements to

        Returns:
            Tuple of (modified_sql, replacement_count)
        """
        replacement_count = 0
        modified_sql = sql_content

        # Replace CURRENT_DATE with DATE('{load_start_date}')
        # This matches CURRENT_DATE as a function call or standalone
        patterns = [
            (r"\bCURRENT_DATE\(\)", "DATE('{load_start_date}')"),  # CURRENT_DATE()
            (
                r"\bCURRENT_DATE\b(?!\()",
                "DATE('{load_start_date}')",
            ),  # CURRENT_DATE (without parentheses)
        ]

        for pattern, replacement in patterns:
            matches = len(re.findall(pattern, modified_sql, re.IGNORECASE))
            if matches > 0:
                modified_sql = re.sub(
                    pattern, replacement, modified_sql, flags=re.IGNORECASE
                )
                replacement_count += matches

        return modified_sql, replacement_count

    def transpile_sql(self, sql_content: str) -> Tuple[Optional[str], Optional[str]]:
        """
        Transpile SQL from Trino to Databricks syntax

        Args:
            sql_content: The SQL content to transpile

        Returns:
            Tuple of (transpiled_sql, error_message)
            If successful, error_message is None
            If failed, transpiled_sql is None
        """
        try:
            # Use sqlglot to transpile from Trino to Databricks
            transpiled = transpile(
                sql_content,
                read=self.SOURCE_DIALECT,
                write=self.TARGET_DIALECT,
                pretty=True,
            )

            if not transpiled:
                return None, "Transpilation returned empty result"

            # Join multiple statements if present
            result = ";\n".join(transpiled)

            # Apply custom replacements
            result, replacements = self.apply_custom_replacements(result)
            self.current_date_replacements += replacements

            # Add a newline at the end if the original had one
            if sql_content.endswith("\n") and not result.endswith("\n"):
                result += "\n"

            return result, None

        except Exception as e:
            return None, f"Transpilation error: {str(e)}"

    def transpile_file(self, file_path: str) -> bool:
        """
        Transpile a single SQL file from Trino to Databricks syntax

        Args:
            file_path: Path to the SQL file

        Returns:
            True if successful, False otherwise
        """
        try:
            # Read the original file
            with open(file_path, encoding="utf-8") as f:
                original_content = f.read()

            if not original_content.strip():
                logger.info(f"⚠️  Skipping empty file: {file_path}")
                self.unchanged_count += 1
                return True

            # Transpile the SQL
            transpiled_content, error = self.transpile_sql(original_content)

            if error:
                logger.info(f"❌ Error transpiling {file_path}: {error}")
                self.errors.append((file_path, error))
                self.error_count += 1
                return False

            # Check if content actually changed
            if transpiled_content == original_content:
                logger.info(f"ℹ️  No changes needed: {file_path}")
                self.unchanged_count += 1
                return True

            # Write the transpiled content back to the file (unless dry run)
            if self.dry_run:
                logger.info(f"🔍 [DRY RUN] Would update: {file_path}")
                logger.info(f"   Original length: {len(original_content)} chars")
                logger.info(f"   New length: {len(transpiled_content)} chars")
            else:
                with open(file_path, "w", encoding="utf-8") as f:
                    f.write(transpiled_content)
                logger.info(f"✅ Successfully transpiled: {file_path}")

            self.success_count += 1
            return True

        except FileNotFoundError:
            error_msg = f"File not found: {file_path}"
            logger.info(f"❌ {error_msg}")
            self.errors.append((file_path, error_msg))
            self.error_count += 1
            return False
        except Exception as e:
            error_msg = f"Unexpected error: {str(e)}"
            logger.info(f"❌ Error processing {file_path}: {error_msg}")
            self.errors.append((file_path, error_msg))
            self.error_count += 1
            return False

    def print_summary(self):
        """Print a summary of the transpilation results"""
        total = self.success_count + self.error_count + self.unchanged_count

        print("\n" + "=" * 60)
        print("TRANSPILATION SUMMARY")
        print("=" * 60)
        print(f"Total files processed: {total}")
        print(f"✅ Successfully transpiled: {self.success_count}")
        print(f"ℹ️  No changes needed: {self.unchanged_count}")
        print(f"❌ Errors: {self.error_count}")

        if self.current_date_replacements > 0:
            print("\n🔄 Custom Replacements:")
            print(
                f"   CURRENT_DATE → DATE('{{load_start_date}}'): {self.current_date_replacements}"
            )

        if self.errors:
            print("\n" + "-" * 60)
            print("ERRORS:")
            print("-" * 60)
            for file_path, error in self.errors:
                print(f"  {file_path}")
                print(f"    └─ {error}")

        print("=" * 60)


class SQLTranspilerRunner:
    """Orchestrates the SQL transpilation process"""

    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.transpiler = SQLTranspiler(dry_run=args.dry_run)
        self.git_service = GitService()

    def get_sql_files_from_git_diff(self) -> List[str]:
        """
        Get all new or modified SQL files from git diff

        Returns:
            List of SQL file paths
        """
        logger.info(f"Comparing {self.args.from_branch} with {self.args.to_branch}...")

        # Fetch the latest changes
        if self.args.fetch:
            branch_name = self.args.from_branch.replace("origin/", "")
            logger.info(f"Fetching latest changes from {branch_name}...")
            self.git_service.fetch(branch_name)

        # Get modified files
        modified_files = self.git_service.get_modified_files_from_diff(
            self.args.from_branch, self.args.to_branch
        )

        # Check if any modified files are in dags/planning_and_performance folder
        has_planning_and_performance_changes = any(
            "dags/planning_and_performance" in file_path
            for file_path in modified_files.keys()
        )

        if not has_planning_and_performance_changes:
            logger.info(
                "ℹ️  No modified files found in dags/planning_and_performance folder."
            )
            logger.info("ℹ️  Skipping SQL transpilation.")
            return []

        logger.info("✓ Found changes in dags/planning_and_performance folder.")

        # Filter for SQL files that are new or modified AND in planning_and_performance folder
        sql_files = [
            file_path
            for file_path, status in modified_files.items()
            if file_path.endswith(".sql")
            and status in self.git_service.NEW_OR_MODIFIED_FILE_STATUS
            and "dags/planning_and_performance" in file_path
        ]

        return sql_files

    def get_sql_files_from_directory(self, directory: str) -> List[str]:
        """
        Get all SQL files from a directory recursively

        Args:
            directory: Directory path to search

        Returns:
            List of SQL file paths
        """
        sql_files = []
        for root, dirs, files in os.walk(directory):
            for file in files:
                if file.endswith(".sql"):
                    sql_files.append(os.path.join(root, file))
        return sql_files

    def run(self):
        """Execute the transpilation based on the selected mode"""
        sql_files = []

        if self.args.mode == "git-diff":
            sql_files = self.get_sql_files_from_git_diff()
            if not sql_files:
                logger.info("No new or modified SQL files found to transpile.")
                logger.info("✓ Transpilation skipped successfully.")
                return 0
            logger.info(
                f"Found {len(sql_files)} SQL file(s) to transpile from git diff."
            )

        elif self.args.mode == "single-file":
            if not os.path.exists(self.args.file):
                logger.info(f"Error: File not found: {self.args.file}")
                return 1
            sql_files = [self.args.file]
            logger.info(f"Transpiling single file: {self.args.file}")

        elif self.args.mode == "directory":
            if not os.path.exists(self.args.directory):
                logger.info(f"Error: Directory not found: {self.args.directory}")
                return 1
            sql_files = self.get_sql_files_from_directory(self.args.directory)
            if not sql_files:
                logger.info(f"No SQL files found in directory: {self.args.directory}")
                return 0
            logger.info(
                f"Found {len(sql_files)} SQL file(s) to transpile in directory."
            )

        # Transpile all SQL files
        logger.info(
            f"\nTranspiling from {self.transpiler.SOURCE_DIALECT} to {self.transpiler.TARGET_DIALECT}...\n"
        )

        for sql_file in sql_files:
            self.transpiler.transpile_file(sql_file)

        # Print summary
        self.transpiler.print_summary()

        # Return exit code based on errors
        return 1 if self.transpiler.error_count > 0 else 0


def main():
    parser = argparse.ArgumentParser(
        description="Transpile SQL files from Trino to Databricks syntax using sqlglot",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Transpile all new/modified SQL files in a git diff
  python sql_transcript.py --mode git-diff --from-branch origin/master --to-branch HEAD
  
  # Transpile a specific SQL file
  python sql_transcript.py --mode single-file --file dags/example/query.sql
  
  # Transpile all SQL files in a directory
  python sql_transcript.py --mode directory --directory dags/fintech/
  
  # Dry run to preview changes
  python sql_transcript.py --mode git-diff --from-branch origin/master --to-branch HEAD --dry-run
        """,
    )

    parser.add_argument(
        "--mode",
        choices=["git-diff", "single-file", "directory"],
        required=True,
        help="Transpilation mode: git-diff, single-file, or directory",
    )

    parser.add_argument(
        "--from-branch",
        default=resolve_diff_from_ref(os.environ.get("CI_COMMIT_BRANCH", "")),
        help="Source branch for git diff comparison (defaults to the CI target)",
    )

    parser.add_argument(
        "--to-branch",
        default="HEAD",
        help="Target branch for git diff comparison (default: HEAD)",
    )

    parser.add_argument("--file", help="Path to a single SQL file to transpile")

    parser.add_argument(
        "--directory", help="Path to directory containing SQL files to transpile"
    )

    parser.add_argument(
        "--fetch",
        action="store_true",
        default=False,
        help="Fetch latest changes from remote before comparing (only for git-diff mode)",
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        default=False,
        help="Show what would be changed without actually modifying files",
    )

    args = parser.parse_args()

    # Validate arguments based on mode
    if args.mode == "single-file" and not args.file:
        parser.error("--file is required for single-file mode")
    elif args.mode == "directory" and not args.directory:
        parser.error("--directory is required for directory mode")

    # Run the transpiler
    runner = SQLTranspilerRunner(args)
    exit_code = runner.run()
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
