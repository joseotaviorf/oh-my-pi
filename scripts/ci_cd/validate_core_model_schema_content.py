#!/usr/bin/env python3
"""
Validation script to ensure core model schema files follow the correct YAML schema structure.

This script:
1. Finds all core model DAGs in dags/core/
2. Extracts table names from tables_customization in declaration files
3. Validates that corresponding schema files exist and have correct content structure
4. Checks YAML syntax, required fields, and schema format
5. Reports validation errors and exits with error code if any are found
6. Supports git-based validation to only check changed files
"""

import argparse
import os
import sys
import yaml
from pathlib import Path
from typing import Dict, List, Set, Tuple, Any

# Import GitService for git-based validation and SchemaValidator for centralized types
sys.path.append(str(Path(__file__).parent.parent))
from services.git_service import GitService
from bietlejuice.base.core_models.helpers.schema_validator import SchemaValidator


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
    if not path.suffix.lower() in ['.yml', '.yaml']:
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


def extract_tables_from_declaration(declaration_file: Path) -> Tuple[str, str, Set[str]]:
    """
    Extract table names from a declaration file.

    Returns:
        Tuple of (dag_name, layer, set_of_table_names)
    """
    try:
        with open(declaration_file, 'r') as f:
            declaration = yaml.safe_load(f)

        dag_name = declaration.get('dag', {}).get('name', '')
        workflow = declaration.get('workflow', {})
        layer = workflow.get('layer', '')
        tables_customization = workflow.get('tables_customization', {})

        # Extract table names from tables_customization
        table_names = set(tables_customization.keys())

        return dag_name, layer, table_names

    except Exception as e:
        print(f"❌ Error reading declaration file {declaration_file}: {e}")
        return '', '', set()


def validate_yaml_syntax(schema_file: Path) -> Tuple[bool, str, Dict]:
    """
    Validate YAML syntax of a schema file.

    Returns:
        Tuple of (is_valid, error_message, parsed_content)
    """
    try:
        with open(schema_file, 'r') as f:
            content = yaml.safe_load(f)
        return True, "", content
    except yaml.YAMLError as e:
        return False, f"YAML syntax error: {str(e)}", {}
    except Exception as e:
        return False, f"File read error: {str(e)}", {}


def validate_schema_structure(content: Dict, schema_file: Path) -> List[str]:
    """
    Validate the structure and content of a schema file.

    Returns:
        List of validation error messages
    """
    errors = []

    # Check if content is a dictionary
    if not isinstance(content, dict):
        errors.append("Schema file must contain a YAML dictionary")
        return errors

    # Check required top-level fields
    required_fields = ['columns']
    for field in required_fields:
        if field not in content:
            errors.append(f"Missing required field: '{field}'")

    # Check min_columns and max_columns - they should be present for documentation and validation
    if 'min_columns' not in content:
        errors.append("Missing required field: 'min_columns' (required for column count validation)")
    if 'max_columns' not in content:
        errors.append("Missing required field: 'max_columns' (required for column count validation)")

    # Validate columns structure
    if 'columns' in content:
        columns = content['columns']
        if not isinstance(columns, dict):
            errors.append("'columns' must be a dictionary")
        else:
            # Validate each column definition
            for col_name, col_def in columns.items():
                if not isinstance(col_def, dict):
                    errors.append(f"Column '{col_name}' definition must be a dictionary")
                    continue

                # Check required column fields
                required_col_fields = ['type', 'required']
                for field in required_col_fields:
                    if field not in col_def:
                        errors.append(f"Column '{col_name}' missing required field: '{field}'")

                # Validate field types and values
                if 'type' in col_def:
                    valid_types = SchemaValidator.VALID_SCHEMA_TYPES
                    if col_def['type'] not in valid_types:
                        errors.append(f"Column '{col_name}' has invalid type '{col_def['type']}'. Valid types: {', '.join(valid_types)}")

                if 'required' in col_def:
                    if not isinstance(col_def['required'], bool):
                        errors.append(f"Column '{col_name}' 'required' field must be a boolean")

    # Validate min_columns and max_columns
    if 'min_columns' in content:
        if not isinstance(content['min_columns'], int) or content['min_columns'] < 0:
            errors.append("'min_columns' must be a non-negative integer")

    if 'max_columns' in content:
        if not isinstance(content['max_columns'], int) or content['max_columns'] < 0:
            errors.append("'max_columns' must be a non-negative integer")

    # Validate min_columns <= max_columns (only if both are integers)
    if 'min_columns' in content and 'max_columns' in content:
        if isinstance(content['min_columns'], int) and isinstance(content['max_columns'], int):
            if content['min_columns'] > content['max_columns']:
                errors.append("'min_columns' cannot be greater than 'max_columns'")

    # Validate strict field if present
    if 'strict' in content:
        if not isinstance(content['strict'], bool):
            errors.append("'strict' field must be a boolean")

    # Validate column count matches min/max constraints
    if 'columns' in content and isinstance(content['columns'], dict):
        column_count = len(content['columns'])
        if 'min_columns' in content and isinstance(content['min_columns'], int) and column_count < content['min_columns']:
            errors.append(f"Column count ({column_count}) is less than min_columns ({content['min_columns']})")
        if 'max_columns' in content and isinstance(content['max_columns'], int) and column_count > content['max_columns']:
            errors.append(f"Column count ({column_count}) is greater than max_columns ({content['max_columns']})")

        # Additional validation for strict mode
        if content.get('strict', False):
            if 'min_columns' in content and 'max_columns' in content:
                if isinstance(content['min_columns'], int) and isinstance(content['max_columns'], int):
                    if content['min_columns'] != content['max_columns']:
                        errors.append(f"In strict mode, min_columns ({content['min_columns']}) should equal max_columns ({content['max_columns']}) since exact column count is enforced")
                    if column_count != content['min_columns']:
                        errors.append(f"In strict mode, actual column count ({column_count}) should equal min_columns ({content['min_columns']})")

    return errors


def validate_schema_file_content(schema_file: Path) -> List[str]:
    """
    Validate the content of a single schema file.

    Returns:
        List of validation error messages
    """
    errors = []

    # Check if file exists
    if not schema_file.exists():
        errors.append(f"Schema file does not exist: {schema_file}")
        return errors

    # Validate YAML syntax
    is_valid_yaml, yaml_error, content = validate_yaml_syntax(schema_file)
    if not is_valid_yaml:
        errors.append(yaml_error)
        return errors

    # Validate schema structure
    structure_errors = validate_schema_structure(content, schema_file)
    errors.extend(structure_errors)

    return errors


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
            dag_name, layer, table_names = extract_tables_from_declaration(declaration_file)
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
                if file_path.endswith('.yml') and '/schemas/' in file_path:
                    schema_files_set.add((Path(file_path), status))
                # Check if it's a declaration file (which might affect schema requirements)
                elif file_path.endswith('_declaration.yml') and '/core/' in file_path:
                    # If declaration file changed, we need to validate all schemas for that DAG
                    dag_dir = Path(file_path).parent
                    declaration_file = dag_dir / f"{dag_dir.name}_declaration.yml"
                    dag_name, layer, table_names = extract_tables_from_declaration(declaration_file)
                    if dag_name and layer and table_names:
                        for table_name in table_names:
                            schema_file = dag_dir / "schemas" / layer / f"{table_name}.yml"
                            schema_files_set.add((schema_file, status))

        # Convert set back to list
        files = list(schema_files_set)

    return files


def validate_core_model_schema_content(mode="all_files", input=None, verbose=False) -> bool:
    """
    Validate that all core model schema files have correct content structure.

    Returns:
        True if all schemas are valid, False otherwise
    """
    if mode == "all_files":
        print("🔍 Validating all core model schema file content...")
    elif mode == "branch":
        print(f"🔍 Validating core model schema file content for branch: {input}")
    elif mode == "file":
        print(f"🔍 Validating schema file content: {input}")

    # Get files to validate
    files_to_validate = get_schema_files_to_validate(mode, input)

    if not files_to_validate:
        if mode == "branch":
            print("✅ No core model schema files to validate in this branch")
        else:
            print("❌ No core model schema files found")
        return True

    print(f"📁 Found {len(files_to_validate)} schema files to validate")

    all_errors = []
    valid_schemas = 0

    for schema_file, status in files_to_validate:
        if verbose:
            print(f"\n🔍 Validating {schema_file} (status: {status})")
        else:
            print(f"   🔍 Validating {schema_file.name}...")

        errors = validate_schema_file_content(schema_file)
        if errors:
            print(f"   ❌ {schema_file.name} - {len(errors)} error(s)")
            for error in errors:
                all_errors.append(f"{schema_file}: {error}")
                if verbose:
                    print(f"      • {error}")
        else:
            print(f"   ✅ {schema_file.name} - Valid")
            valid_schemas += 1

    print(f"\n📊 Validation Summary:")
    print(f"   Total files: {len(files_to_validate)}")
    print(f"   Valid: {valid_schemas}")
    print(f"   Invalid: {len(all_errors)}")

    if all_errors:
        print(f"\n❌ Schema content validation errors:")
        for error in sorted(all_errors):
            print(f"   • {error}")

        print(f"\n💡 Schema file structure should follow this format:")
        print(f"   columns:")
        print(f"     column_name:")
        print(f"       type: {'|'.join(SchemaValidator.VALID_SCHEMA_TYPES)}")
        print(f"       required: true|false")
        print(f"       nullable: true|false  # Optional: not validated (Spark auto-infers)")
        print(f"   min_columns: <number>  # Required: minimum column count")
        print(f"   max_columns: <number>  # Required: maximum column count")
        print(f"   strict: true|false     # Optional: if true, only exact columns allowed")
        print(f"   ")
        print(f"   Note: In strict mode, min_columns should equal max_columns and actual column count")
        print(f"   Note: nullable field is not validated since Spark auto-infers schema")
        return False
    else:
        print(f"\n✅ All core model schema files have valid content!")
        return True


def main():
    """Main entry point."""
    mode, input, verbose = parse_args()
    success = validate_core_model_schema_content(mode, input, verbose)

    if not success:
        print(f"\n❌ Schema content validation failed!")
        sys.exit(1)
    else:
        print(f"\n✅ Schema content validation passed!")
        sys.exit(0)


if __name__ == "__main__":
    main()
