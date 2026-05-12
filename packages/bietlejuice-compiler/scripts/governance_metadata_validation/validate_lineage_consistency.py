"""
Validates that metadata files (lineage) are consistent with their corresponding SQL queries.

This script ensures that:
1. All columns in the metadata file exist in the SQL query result
2. All columns in the SQL query result are documented in the metadata file
3. Column names match exactly (case-sensitive)

Usage:
    python validate_lineage_consistency.py -a              # Validate all files
    python validate_lineage_consistency.py -b <branch>     # Validate changed files in branch
    python validate_lineage_consistency.py -f <file_path>  # Validate single file
"""

import argparse
import os
import re
from pathlib import Path
from typing import Dict, List, Set, Tuple

import yaml
from sqlglot import exp, parse_one

from scripts.ci_cd.domain_cli import (
    branch_name_arg_type,
    domain_arg_type,
    repo_relative_file_arg_type,
)
from scripts.services.git_service import GitService
from scripts.services.metadata_file_service import MetadataFileService

# Load skip lists
with open(f"{Path(__file__).parent}/skip_list.yml") as f:
    SKIP_LIST_DATA = yaml.safe_load(f)
    SKIP_LIST_METADATA = SKIP_LIST_DATA.get("metadata_files_out_of_pattern", [])
    SKIP_LIST_QUERIES = SKIP_LIST_DATA.get("queries_without_metadata_files", [])
    PARSING_SKIP_LIST = set(SKIP_LIST_DATA.get("parsing_skip_list", []))

SKIP_LIST_PATH_REGEX = re.compile(r"(?:.*/)?dags/(?P<path>.*)")

metadata_file_service = MetadataFileService()


class LineageConsistencyError(Exception):
    """Exception raised when lineage is inconsistent with SQL query."""

    pass


def parse_args():
    parser = argparse.ArgumentParser(
        description="Validate that metadata files are consistent with SQL queries"
    )
    parser.add_argument(
        "-v",
        "--verbose",
        help="Output more detailed messages",
        action="store_true",
        required=False,
    )
    parser.add_argument(
        "--domain",
        help="Restrict validation to a specific domain folder under dags/ (e.g. for_rent, fintech)",
        type=domain_arg_type,
        required=False,
        default=None,
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "-f",
        "--file",
        help="Path to a metadata or SQL file to be validated",
        type=repo_relative_file_arg_type,
        required=False,
    )
    group.add_argument(
        "-b",
        "--branch",
        help="Branch to be validated",
        type=branch_name_arg_type,
        required=False,
    )
    group.add_argument(
        "-a",
        "--all-files",
        help="Validate all metadata files",
        action="store_true",
        required=False,
    )
    args = parser.parse_args()
    # args.file and args.domain are already sanitized by the argparse type= callbacks
    # above, so no further sanitization is needed here.
    mode = None
    input_value = None
    if args.file:
        mode = "file"
        input_value = args.file
    elif args.branch is not None:  # detect via presence, not truthiness (value may be "")
        mode = "branch"
        input_value = args.branch
    elif args.all_files:
        mode = "all_files"
        input_value = args.all_files

    return mode, input_value, args.verbose, args.domain


def normalize_sql(sql: str) -> str:
    """
    Normalizes SQL by removing Jinja2 templates and replacing with safe values.
    This ensures the SQL can be parsed by sqlglot.
    
    Note: SQL files may have regex patterns like {{2}} (escaped for Jinja2) which 
    should become {2} after normalization, not 'DUMMY_VALUE'.
    """
    # Remove comments first (before processing templates)
    sql = re.sub(r"--.*$", "", sql, flags=re.MULTILINE)
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.DOTALL)

    # Normalize SQL functions with empty parentheses (both syntaxes are valid in Spark SQL)
    # CURRENT_DATE() -> CURRENT_DATE, CURRENT_TIMESTAMP() -> CURRENT_TIMESTAMP
    sql = re.sub(
        r"\b(CURRENT_DATE|CURRENT_TIMESTAMP)\(\)", r"\1", sql, flags=re.IGNORECASE
    )

    # Step 1: Unescape regex quantifiers that were escaped for Jinja2
    # Example: {{2}} -> {2}, {{10}} -> {10}
    sql = re.sub(r"\{\{(\d+)\}\}", r"{\1}", sql)
    sql = re.sub(r"\{\{(\d+),(\d+)\}\}", r"{\1,\2}", sql)  # Handle {2,10} patterns
    sql = re.sub(r"\{\{,(\d+)\}\}", r"{,\1}", sql)  # Handle {,10} patterns
    sql = re.sub(r"\{\{(\d+),\}\}", r"{\1,}", sql)  # Handle {10,} patterns

    # Step 2: Replace Jinja2 variables (with spaces or identifiers) with dummy values
    # This matches {{ variable }}, {{ some_var }}, etc. but NOT {{2}} (already handled)
    # Look for patterns with at least one space OR one letter/underscore
    sql = re.sub(r"\{\{\s*[a-zA-Z_][a-zA-Z0-9_\s]*\s*\}\}", "'DUMMY_VALUE'", sql)

    # Step 3: Replace single-brace template variables like {year}, {month}, {day}
    # Three scenarios:
    # A) Composite template strings: '{year}-{month}-{day}' -> '2024-01-01' (handle FIRST)
    # B) Already inside quotes: '{year}' -> 'DUMMY_VALUE' (remove the template, keep quotes)
    # C) Not in quotes: {year} -> 'DUMMY_VALUE' (add quotes)

    # A) Handle composite template strings like '{year}-{month}-{day}' or '{start_date}'
    #    This pattern matches strings with one or more templates separated by -, /, :, or space
    #    Must come BEFORE individual template replacement to avoid breaking the string
    sql = re.sub(
        r"'(?:\{[a-zA-Z_][a-zA-Z0-9_]*\}[-/:\s]?)+\{[a-zA-Z_][a-zA-Z0-9_]*\}'",
        "'2024-01-01'",
        sql,
    )

    # B) Handle templates already inside single quotes: '{template}' -> 'DUMMY_VALUE'
    sql = re.sub(r"'\{([a-zA-Z_][a-zA-Z0-9_]*)\}'", "'DUMMY_VALUE'", sql)

    # C) Handle templates not in quotes: {template} -> 'DUMMY_VALUE'
    sql = re.sub(r"\{([a-zA-Z_][a-zA-Z0-9_]*)\}", r"'DUMMY_VALUE'", sql)

    return sql


def extract_columns_from_sql(sql_file_path: str) -> Tuple[Set[str], bool]:
    """
    Parses a SQL file and extracts the column names from the final SELECT statement.
    
    Args:
        sql_file_path: Path to the SQL file
        
    Returns:
        Tuple of (Set of column names (lowercase for comparison), has_select_star)
        has_select_star is True if the final SELECT uses SELECT *
        
    Raises:
        Exception: If SQL cannot be parsed
    """
    try:
        _project_root = os.path.realpath(os.getcwd())
        _resolved_sql = os.path.realpath(sql_file_path)
        if not _resolved_sql.startswith(_project_root + os.sep):
            raise ValueError(f"Path {sql_file_path!r} escapes the project root")
        with open(_resolved_sql, "r", encoding="utf-8") as f:
            sql = f.read()

        normalized_sql = normalize_sql(sql)
        # Using 'databricks' dialect instead of 'spark' for better compatibility
        # Databricks dialect supports more Spark SQL features (e.g., bracket notation for JSON fields)
        sql_parser = parse_one(normalized_sql, read="databricks")
        final_select = sql_parser.find(exp.Select)

        if not final_select:
            raise Exception("No SELECT statement found in SQL")

        columns = set()
        has_select_star = False
        for column in final_select.expressions:
            # Check if this is a SELECT * (Star expression)
            if isinstance(column, exp.Star):
                has_select_star = True
            else:
                col_name = column.alias_or_name
                if col_name == "*":
                    has_select_star = True
                elif col_name:
                    columns.add(col_name.lower())

        return columns, has_select_star

    except Exception as e:
        raise Exception(f"Error parsing SQL file {sql_file_path}: {str(e)}")


def extract_columns_from_metadata(metadata_file_path: str) -> Set[str]:
    """
    Reads a metadata file and extracts the documented column names.
    
    Args:
        metadata_file_path: Path to the metadata YAML file
        
    Returns:
        Set of column names (lowercase for comparison)
        
    Raises:
        Exception: If metadata file cannot be read or parsed
    """
    try:
        _project_root = os.path.realpath(os.getcwd())
        _resolved_meta = os.path.realpath(metadata_file_path)
        if not _resolved_meta.startswith(_project_root + os.sep):
            raise ValueError(f"Path {metadata_file_path!r} escapes the project root")
        with open(_resolved_meta, "r", encoding="utf-8") as f:
            metadata = yaml.safe_load(f)

        if not metadata or "columns" not in metadata:
            raise Exception("No columns section found in metadata file")

        columns = set(col.lower() for col in metadata["columns"].keys())
        return columns

    except Exception as e:
        raise Exception(f"Error reading metadata file {metadata_file_path}: {str(e)}")


def get_sql_path_from_metadata(metadata_path: str) -> str:
    """
    Given a metadata file path, returns the corresponding SQL file path.
    Example: dags/domain/dag_name/metadata/layer/table.yml -> dags/domain/dag_name/queries/layer/table.sql
    """
    return (
        metadata_path.replace("/metadata/", "/queries/")
        .replace(".yml", ".sql")
        .replace(".yaml", ".sql")
    )


def get_metadata_path_from_sql(sql_path: str) -> str:
    """
    Given a SQL file path, returns the corresponding metadata file path.
    Example: dags/domain/dag_name/queries/layer/table.sql -> dags/domain/dag_name/metadata/layer/table.yml
    """
    yml_path = sql_path.replace("/queries/", "/metadata/").replace(".sql", ".yml")
    yaml_path = sql_path.replace("/queries/", "/metadata/").replace(".sql", ".yaml")

    if os.path.exists(yml_path):
        return yml_path
    elif os.path.exists(yaml_path):
        return yaml_path
    else:
        return yml_path  # Return default even if doesn't exist


def validate_lineage_consistency(sql_path: str, metadata_path: str) -> Dict:
    """
    Validates that a metadata file is consistent with its SQL query.
    
    Args:
        sql_path: Path to SQL file
        metadata_path: Path to metadata file
        
    Returns:
        Dict with validation results:
        {
            'valid': bool,
            'errors': List[str],
            'error_type': str ('parsing', 'consistency', 'metadata', or None),
            'sql_columns': Set[str],
            'metadata_columns': Set[str],
            'has_select_star': bool
        }
    """
    result = {
        "valid": True,
        "errors": [],
        "error_type": None,
        "sql_columns": set(),
        "metadata_columns": set(),
        "has_select_star": False,
    }

    try:
        # Extract columns from both sources
        sql_columns, has_select_star = extract_columns_from_sql(sql_path)
        metadata_columns = extract_columns_from_metadata(metadata_path)

        result["sql_columns"] = sql_columns
        result["metadata_columns"] = metadata_columns
        result["has_select_star"] = has_select_star

        # Special handling for SELECT * case
        if has_select_star:
            result["valid"] = False
            result["error_type"] = "consistency"
            result["errors"].append(
                "SQL query uses SELECT * which prevents column validation. "
                "Please explicitly list all columns in the SELECT statement to enable metadata validation."
            )
            return result

        # Check for columns in SQL but not in metadata
        missing_in_metadata = sql_columns - metadata_columns
        if missing_in_metadata:
            result["valid"] = False
            result["error_type"] = "consistency"
            result["errors"].append(
                f"Columns in SQL query but missing in metadata: {sorted(missing_in_metadata)}"
            )

        # Check for columns in metadata but not in SQL
        missing_in_sql = metadata_columns - sql_columns
        if missing_in_sql:
            result["valid"] = False
            result["error_type"] = "consistency"
            result["errors"].append(
                f"Columns in metadata but missing in SQL query: {sorted(missing_in_sql)}"
            )

    except Exception as e:
        result["valid"] = False
        error_msg = str(e)

        # Detect if it's a parsing error or metadata reading error
        if "Error parsing SQL file" in error_msg:
            result["error_type"] = "parsing"
        elif "Error reading metadata file" in error_msg:
            result["error_type"] = "metadata"
        else:
            result["error_type"] = "unknown"

        result["errors"].append(error_msg)

    return result


def remove_prefix(input_string: str) -> str:
    """Remove path prefix to match skip list format."""
    match = re.match(SKIP_LIST_PATH_REGEX, input_string)
    if match:
        return match.groupdict()["path"]
    return input_string


def should_skip_file(file_path: str) -> bool:
    """Check if file is in skip list."""
    relative_path = remove_prefix(file_path)
    return relative_path in SKIP_LIST_METADATA or relative_path in SKIP_LIST_QUERIES


def _find_file_pair_by_user_input(user_input: str) -> List[Tuple[str, str, str]]:
    """Return the (sql_path, metadata_path, status) pair that matches *user_input*.

    The user-supplied value is used ONLY as a filter criterion via string
    equality comparison — it is never passed to open() or used to construct
    a filesystem path.  The paths that are returned (and later opened) come
    exclusively from Path.rglob(), which enumerates the dags/ tree
    independently of anything the user provided.  This pattern prevents
    Snyk's taint engine from tracing CLI input into file-system operations
    (CWE-23).
    """
    base = Path("dags")

    for sql_path in base.rglob("queries/**/*.sql"):
        sql_str = str(sql_path).replace("\\", "/")
        if sql_str == user_input:
            metadata_path = get_metadata_path_from_sql(sql_str)
            if os.path.exists(metadata_path):
                return [(sql_str, metadata_path, "M")]
            print(f"⚠️ Warning: Could not find metadata for {sql_str}")
            return []

    for meta_path in base.rglob("metadata/**/*.yml"):
        meta_str = str(meta_path).replace("\\", "/")
        if meta_str == user_input:
            sql_path_str = get_sql_path_from_metadata(meta_str)
            if os.path.exists(sql_path_str):
                return [(sql_path_str, meta_str, "M")]
            print(f"⚠️ Warning: Could not find SQL for {meta_str}")
            return []

    for meta_path in base.rglob("metadata/**/*.yaml"):
        meta_str = str(meta_path).replace("\\", "/")
        if meta_str == user_input:
            sql_path_str = get_sql_path_from_metadata(meta_str)
            if os.path.exists(sql_path_str):
                return [(sql_path_str, meta_str, "M")]
            print(f"⚠️ Warning: Could not find SQL for {meta_str}")
            return []

    print(f"⚠️ Warning: File {user_input!r} not found under dags/ (queries/ or metadata/)")
    return []


def get_files_to_validate(mode: str, input_value) -> List[Tuple[str, str, str]]:
    """
    Get list of files to validate based on mode.

    Domain filtering is intentionally absent here — callers apply it after
    the fact using plain string comparison so that no user-supplied value
    ever participates in path construction inside this function.

    Returns:
        List of tuples: (sql_path, metadata_path, status)
    """
    files = []

    if mode == "file":
        # Single file mode — look up the file via rglob so that user-supplied
        # input is used only as a comparison value, never as a path to open().
        return _find_file_pair_by_user_input(input_value)

    elif mode == "branch":
        # Git diff mode — branch name is used only for comparison, not as a path
        git_service = GitService()
        from_branch = "HEAD~1" if input_value == "master" else "origin/master"

        changed_files_dict = git_service.get_modified_files_from_diff(
            from_branch, "HEAD"
        )

        # Convert dict to list of tuples and filter by status
        changed_files = [
            (file, status)
            for file, status in changed_files_dict.items()
            if status in GitService.UPSERT_STATUS_CODES
        ]

        # Process only SQL and metadata files in relevant layers
        # Use a set to track processed pairs and avoid duplicates
        processed_pairs = set()

        for file_path, status in changed_files:
            if status == "D":  # Skip deleted files
                continue

            # Check if file is in a layer that requires validation
            # Note: Core models are excluded because they use Spark jobs (Python) instead of SQL queries
            if not any(
                layer in file_path
                for layer in ["/raw/", "/clean/", "/enrich/", "/dw/", "/metric/"]
            ):
                continue

            # Explicitly skip core and reverse layer files
            if "/core/" in file_path or "/reverse/" in file_path:
                continue

            if "/metadata/" in file_path and (
                file_path.endswith(".yml") or file_path.endswith(".yaml")
            ):
                sql_path = get_sql_path_from_metadata(file_path)
                if os.path.exists(sql_path) and os.path.exists(file_path):
                    pair_key = (sql_path, file_path)
                    if pair_key not in processed_pairs:
                        files.append((sql_path, file_path, status))
                        processed_pairs.add(pair_key)

            elif "/queries/" in file_path and file_path.endswith(".sql"):
                metadata_path = get_metadata_path_from_sql(file_path)
                if os.path.exists(file_path) and os.path.exists(metadata_path):
                    pair_key = (file_path, metadata_path)
                    if pair_key not in processed_pairs:
                        files.append((file_path, metadata_path, status))
                        processed_pairs.add(pair_key)

    elif mode == "all_files":
        # Always scan the whole dags/ tree — domain filtering is done by the
        # caller so that no user-supplied value ever enters path construction.
        base_dags_dir = Path("dags")
        if not base_dags_dir.exists():
            print("Error: directory not found: dags/")
            return files

        # Find all SQL files in queries folders
        for sql_path in base_dags_dir.rglob("queries/**/*.sql"):
            sql_path_str = str(sql_path)

            # Check if in relevant layer (excluding core and reverse)
            # Note: Core models use Spark jobs (Python) instead of SQL queries
            if not any(
                layer in sql_path_str
                for layer in ["/raw/", "/clean/", "/enrich/", "/dw/", "/metric/"]
            ):
                continue

            # Explicitly skip core and reverse layer files
            if "/core/" in sql_path_str or "/reverse/" in sql_path_str:
                continue

            metadata_path = get_metadata_path_from_sql(sql_path_str)
            if os.path.exists(metadata_path):
                files.append((sql_path_str, metadata_path, "A"))

    return files


def _sql_paths_for_domain(domain: str) -> Set[str]:
    """Return the set of SQL paths (from the filesystem) that live under dags/<domain>/.

    *domain* is used ONLY as a comparison value inside a loop condition —
    it is never concatenated into a path or passed to open().  The returned
    set is built entirely from Path.iterdir() / Path.rglob() results, so
    Snyk's taint engine cannot trace CLI input through to file-system
    operations via this function's return value.
    """
    result: Set[str] = set()
    for d in Path("dags").iterdir():
        if d.is_dir() and d.name == domain:  # domain used only in comparison
            for sql in d.rglob("queries/**/*.sql"):
                result.add(str(sql).replace("\\", "/"))
            break
    return result


def output_results(results: Dict, verbose: bool):
    """Print validation results with clear categorization."""
    print("\n" + "=" * 80)
    print("VALIDATION RESULTS")
    print("=" * 80 + "\n")

    # Show passed files
    if results["passed"]:
        print(f"✅ PASSED: {len(results['passed'])} file(s)")
        if verbose:
            for sql_path, metadata_path in results["passed"]:
                print(f"  - {metadata_path}")

    # Show parsing skip list files (warning but not error)
    if results["skipped_parsing"]:
        print(f"\n⚠️  PARSING SKIP LIST: {len(results['skipped_parsing'])} file(s)")
        print(
            "    These files use advanced Spark SQL features not fully supported by the parser."
        )
        print("    They are skipped from validation to avoid blocking CI/CD.")
        print("    ⚠️  Manual validation recommended when modifying these files!")
        if verbose or len(results["skipped_parsing"]) <= 5:
            for sql_path, metadata_path in results["skipped_parsing"]:
                print(f"    • {sql_path}")

    # Show skipped files
    if results["skipped"]:
        print(f"\n⊘ SKIPPED: {len(results['skipped'])} file(s)")
        if verbose:
            for item in results["skipped"]:
                print(f"  - {item}")

    # Categorize failures by type
    if results["failed"]:
        parsing_errors = []
        select_star_errors = []
        consistency_errors = []
        metadata_errors = []
        other_errors = []

        for sql_path, metadata_path, validation_result in results["failed"]:
            error_type = validation_result.get("error_type", "unknown")
            has_select_star = validation_result.get("has_select_star", False)
            
            if error_type == "parsing":
                parsing_errors.append((sql_path, metadata_path, validation_result))
            elif error_type == "consistency" and has_select_star:
                select_star_errors.append((sql_path, metadata_path, validation_result))
            elif error_type == "consistency":
                consistency_errors.append((sql_path, metadata_path, validation_result))
            elif error_type == "metadata":
                metadata_errors.append((sql_path, metadata_path, validation_result))
            else:
                other_errors.append((sql_path, metadata_path, validation_result))

        # Show parsing errors (critical - should be added to skip list)
        if parsing_errors:
            print(f"\n🔴 PARSING ERRORS: {len(parsing_errors)} file(s)")
            print(
                "    ⚠️  The SQL parser couldn't read these files due to advanced Spark SQL syntax."
            )
            print(
                "    📝 ACTION: Add these files to parsing_skip_list if the SQL is valid in Databricks."
            )
            print(
                "    📖 See: scripts/governance_metadata_validation/skip_list.yml"
            )
            for sql_path, metadata_path, validation_result in parsing_errors:
                print(f"\n    File: {metadata_path}")
                print(f"    SQL:  {sql_path}")
                for error in validation_result["errors"]:
                    # Show only the first 150 chars of parsing error for readability
                    error_msg = error.replace("Error parsing SQL file", "Parser error")
                    if len(error_msg) > 150:
                        error_msg = error_msg[:150] + "..."
                    print(f"      ❌ {error_msg}")

        # Show SELECT * errors (special case)
        if select_star_errors:
            print(f"\n⚠️  SELECT * ERRORS: {len(select_star_errors)} file(s)")
            print("    ⚠️  SQL queries use SELECT * which prevents column validation.")
            print("    📝 ACTION: Replace SELECT * with explicit column names to enable metadata validation.")
            for sql_path, metadata_path, validation_result in select_star_errors:
                print(f"\n    File: {metadata_path}")
                print(f"    SQL:  {sql_path}")
                for error in validation_result["errors"]:
                    print(f"      ❌ {error}")

        # Show consistency errors (expected - need metadata update)
        if consistency_errors:
            print(f"\n⚠️  CONSISTENCY ERRORS: {len(consistency_errors)} file(s)")
            print("    ⚠️  Columns in SQL don't match the metadata documentation.")
            print("    📝 ACTION: Update metadata YAML files to match the SQL queries.")
            for sql_path, metadata_path, validation_result in consistency_errors:
                print(f"\n    File: {metadata_path}")
                print(f"    SQL:  {sql_path}")
                for error in validation_result["errors"]:
                    print(f"      ❌ {error}")

        # Show metadata reading errors
        if metadata_errors:
            print(f"\n❌ METADATA ERRORS: {len(metadata_errors)} file(s)")
            print("    ⚠️  Couldn't read or parse metadata YAML files.")
            for sql_path, metadata_path, validation_result in metadata_errors:
                print(f"\n    File: {metadata_path}")
                for error in validation_result["errors"]:
                    print(f"      ❌ {error}")

        # Show other errors
        if other_errors:
            print(f"\n❓ OTHER ERRORS: {len(other_errors)} file(s)")
            for sql_path, metadata_path, validation_result in other_errors:
                print(f"\n    File: {metadata_path}")
                print(f"    SQL:  {sql_path}")
                for error in validation_result["errors"]:
                    print(f"      ❌ {error}")

    print("\n" + "=" * 80)


def main():
    mode, input_value, verbose, domain = parse_args()

    if mode == "branch" and not input_value:
        import subprocess
        input_value = subprocess.check_output(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"], text=True
        ).strip()

    print(f"\nValidating lineage consistency...")
    print(f"Mode: {mode}")
    if domain:
        print(f"Domain filter: {domain}")
    if mode == "branch":
        print(f"Branch: {input_value}\n")

    files_to_validate = get_files_to_validate(mode, input_value)
    if domain:
        # Build the allowed-path set purely from filesystem enumeration.
        # 'domain' is used ONLY in the comparison 'd.name == domain' — it is
        # never assigned to a variable that feeds into path construction or
        # open().  allowed_sql is populated from Path.rglob() results so
        # Snyk's taint engine cannot trace cli input through to file-system ops.
        allowed_sql: Set[str] = set()
        for _d in Path("dags").iterdir():
            if _d.is_dir() and _d.name == domain:
                for _sql in _d.rglob("queries/**/*.sql"):
                    allowed_sql.add(str(_sql).replace("\\", "/"))
                break
        files_to_validate = [
            (sql, meta, st)
            for sql, meta, st in files_to_validate
            if sql in allowed_sql
        ]

    results = {"passed": [], "failed": [], "skipped": [], "skipped_parsing": []}

    for sql_path, metadata_path, status in files_to_validate:
        # Check skip list
        if should_skip_file(sql_path) or should_skip_file(metadata_path):
            results["skipped"].append(metadata_path)
            continue

        # Check parsing skip list
        if sql_path in PARSING_SKIP_LIST:
            results["skipped_parsing"].append((sql_path, metadata_path))
            continue

        # Validate consistency
        validation_result = validate_lineage_consistency(sql_path, metadata_path)

        if validation_result["valid"]:
            results["passed"].append((sql_path, metadata_path))
        else:
            results["failed"].append((sql_path, metadata_path, validation_result))

    output_results(results, verbose)

    # Exit with error only if there are non-skipped failures
    if results["failed"]:
        print("\nResult: Some metadata files are inconsistent with their SQL queries.")
        print("Please update the metadata files to match the query columns.\n")
        exit(1)
    else:
        print("\nResult: All metadata files are consistent with their SQL queries! ✅\n")
        exit(0)


if __name__ == "__main__":
    main()
