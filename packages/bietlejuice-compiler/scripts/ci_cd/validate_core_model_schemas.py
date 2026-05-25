#!/usr/bin/env python3
"""
Validation script to ensure all core model tables have their corresponding schema files.

This script:
1. Finds all core model DAGs in dags/core/
2. Extracts table names from tables_customization in declaration files
3. Checks if corresponding schema files exist in schemas/{layer}/{table_name}.yml
4. Reports missing schema files and exits with error code if any are found
5. Supports git-based validation to only check changed files
"""

import argparse
import sys
from pathlib import Path
from typing import List, Set, Tuple

import yaml

# Import GitService for git-based validation
sys.path.append(str(Path(__file__).parent.parent))
from services.git_service import GitService


def validate_and_sanitize_file_path(file_path: str) -> Path:
    """
    Validate and sanitize a file path to prevent path traversal attacks.

    Args:
        file_path: The input file path

    Returns:
        Path: A sanitized Path object

    Raises:
        ValueError: If the path is invalid or contains path traversal attempts
    """
    # Convert to Path object
    path = Path(file_path)

    # Resolve the path to get absolute path
    try:
        resolved_path = path.resolve()
    except (OSError, ValueError) as e:
        raise ValueError(f"Invalid file path: {file_path}") from e

    # Check for path traversal attempts
    if ".." in path.parts:
        raise ValueError(f"Path traversal detected in: {file_path}")

    # Ensure the path is within the project directory
    project_root = Path.cwd().resolve()
    try:
        resolved_path.relative_to(project_root)
    except ValueError:
        raise ValueError(f"File path must be within project directory: {file_path}")

    # Check if it's a YAML file
    if path.suffix.lower() not in [".yml", ".yaml"]:
        raise ValueError(f"File must be a YAML file (.yml or .yaml): {file_path}")

    return path


def find_core_model_dags() -> List[Path]:
    """Find all core model DAG directories."""
    core_dir = Path("dags/core")
    if not core_dir.exists():
        print("❌ dags/core directory not found")
        return []

    core_dags = []
    for dag_dir in core_dir.iterdir():
        if dag_dir.is_dir():
            declaration_file = dag_dir / f"{dag_dir.name}_declaration.yml"
            if declaration_file.exists():
                core_dags.append(dag_dir)

    return core_dags


def extract_tables_from_declaration(
    declaration_file: Path,
) -> Tuple[str, str, Set[str]]:
    """
    Extract table names from a declaration file.

    Returns:
        Tuple of (dag_name, layer, set_of_table_names)
    """
    try:
        with open(declaration_file) as f:
            declaration = yaml.safe_load(f)

        dag_name = declaration.get("dag", {}).get("name", "")
        workflow = declaration.get("workflow", {})
        layer = workflow.get("layer", "")
        tables_customization = workflow.get("tables_customization", {})

        # Extract table names from tables_customization
        table_names = set(tables_customization.keys())

        return dag_name, layer, table_names

    except Exception as e:
        print(f"❌ Error reading declaration file {declaration_file}: {e}")
        return "", "", set()


def check_schema_file_exists(dag_dir: Path, layer: str, table_name: str) -> bool:
    """Check if schema file exists for a given table."""
    schema_file = dag_dir / "schemas" / layer / f"{table_name}.yml"
    return schema_file.exists()


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
    group.add_argument(
        "-f", "--file", help="Path to a schema file to be validated", required=False
    )
    group.add_argument("-b", "--branch", help="Branch to be validated", required=False)
    group.add_argument(
        "-a",
        "--all-files",
        help="Validate all schema files",
        action="store_true",
        required=False,
    )
    args = parser.parse_args()
    file = args.file
    branch = args.branch
    all_files = args.all_files
    verbose = args.verbose
    mode = None
    if file:
        mode = "file"
    if branch:
        mode = "branch"
    if all_files:
        mode = "all_files"
    return mode, (file or branch or all_files), verbose


def get_schema_files_to_validate(mode, input) -> List[Tuple[Path, str]]:
    """Get list of schema files to validate based on mode."""
    files = []
    if mode == "file":
        try:
            sanitized_path = validate_and_sanitize_file_path(input)
            files = [(sanitized_path, "A")]
        except ValueError as e:
            print(f"❌ Invalid file path: {e}")
            return []
    elif mode == "all_files":
        # Get all schema files from all core model DAGs
        core_dags = find_core_model_dags()
        for dag_dir in core_dags:
            declaration_file = dag_dir / f"{dag_dir.name}_declaration.yml"
            dag_name, layer, table_names = extract_tables_from_declaration(
                declaration_file
            )
            if dag_name and layer and table_names:
                for table_name in table_names:
                    schema_file = dag_dir / "schemas" / layer / f"{table_name}.yml"
                    files.append((schema_file, "A"))
    elif mode == "branch":
        git_service = GitService()
        if input == "master":
            from_branch = "HEAD~1"
        else:
            from_branch = "origin/master"

        # Get all changed files
        changed_files = git_service.get_modified_files_from_diff(from_branch, "HEAD")

        # Use a set to track unique schema files and their status
        schema_files_set = set()

        # Filter for schema files and declaration files
        for file_path, status in changed_files.items():
            if status in GitService.UPSERT_STATUS_CODES:
                # Check if it's a schema file
                if file_path.endswith(".yml") and "/schemas/" in file_path:
                    schema_files_set.add((Path(file_path), status))
                # Check if it's a declaration file (which might affect schema requirements)
                elif file_path.endswith("_declaration.yml") and "/core/" in file_path:
                    # If declaration file changed, we need to validate all schemas for that DAG
                    dag_dir = Path(file_path).parent
                    declaration_file = dag_dir / f"{dag_dir.name}_declaration.yml"
                    dag_name, layer, table_names = extract_tables_from_declaration(
                        declaration_file
                    )
                    if dag_name and layer and table_names:
                        for table_name in table_names:
                            schema_file = (
                                dag_dir / "schemas" / layer / f"{table_name}.yml"
                            )
                            schema_files_set.add((schema_file, status))

        # Convert set back to list
        files = list(schema_files_set)

    return files


def validate_core_model_schemas(mode="all_files", input=None, verbose=False) -> bool:
    """
    Validate that all core model tables have corresponding schema files.

    Returns:
        True if all schemas exist, False otherwise
    """
    if mode == "all_files":
        print("🔍 Validating all core model schema files...")
    elif mode == "branch":
        print(f"🔍 Validating core model schema files for branch: {input}")
    elif mode == "file":
        print(f"🔍 Validating schema file: {input}")

    # Get files to validate
    files_to_validate = get_schema_files_to_validate(mode, input)

    if not files_to_validate:
        if mode == "branch":
            print("✅ No core model schema files to validate in this branch")
        else:
            print("❌ No core model schema files found")
        return True

    print(f"📁 Found {len(files_to_validate)} schema files to validate")

    missing_schemas = []
    validated_tables = 0

    for schema_file, status in files_to_validate:
        if verbose:
            print(f"\n🔍 Validating {schema_file} (status: {status})")

        if schema_file.exists():
            print(f"   ✅ {schema_file.name}")
            validated_tables += 1
        else:
            print(f"   ❌ {schema_file.name} - MISSING")
            missing_schemas.append(str(schema_file))

    print("\n📊 Validation Summary:")
    print(f"   Total files: {len(files_to_validate)}")
    print(f"   Validated: {validated_tables}")
    print(f"   Missing: {len(missing_schemas)}")

    if missing_schemas:
        print("\n❌ Missing schema files:")
        for schema_path in sorted(missing_schemas):
            print(f"   - {schema_path}")

        print(
            "\n💡 To fix this, create the missing schema files with the expected structure:"
        )
        print("   Example: dags/core/{dag_name}/schemas/{layer}/{table_name}.yml")
        return False
    else:
        print("\n✅ All core model schema files exist!")
        return True


def main():
    """Main entry point."""
    mode, input, verbose = parse_args()
    success = validate_core_model_schemas(mode, input, verbose)

    if not success:
        print("\n❌ Schema validation failed!")
        sys.exit(1)
    else:
        print("\n✅ Schema validation passed!")
        sys.exit(0)


if __name__ == "__main__":
    main()
