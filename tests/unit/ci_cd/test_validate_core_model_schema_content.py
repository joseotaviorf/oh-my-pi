#!/usr/bin/env python3
"""
Unit tests for the core model schema content validation script.
"""

import pytest
import sys
import tempfile
import os
import yaml
from pathlib import Path
from unittest.mock import patch, Mock

# Import the validation functions
sys.path.append(".")
try:
    from scripts.ci_cd.validate_core_model_schema_content import (
        validate_and_sanitize_file_path,
        validate_yaml_syntax,
        validate_schema_structure,
        validate_schema_file_content,
        get_schema_files_to_validate,
        validate_core_model_schema_content,
    )
except ImportError:
    pass


class TestValidateAndSanitizeFilePath:
    """Test cases for file path validation and sanitization."""

    def test_valid_yaml_file_path(self):
        """Test valid YAML file path."""
        # Arrange
        valid_path = "dags/core/core_visit/schemas/core/visit.yml"

        # Act
        result = validate_and_sanitize_file_path(valid_path)

        # Assert
        assert isinstance(result, Path)
        assert result.name == "visit.yml"
        assert result.suffix == ".yml"

    def test_valid_yaml_file_path_with_yaml_extension(self):
        """Test valid YAML file path with .yaml extension."""
        # Arrange
        valid_path = "dags/core/core_visit/schemas/core/visit.yaml"

        # Act
        result = validate_and_sanitize_file_path(valid_path)

        # Assert
        assert isinstance(result, Path)
        assert result.name == "visit.yaml"
        assert result.suffix == ".yaml"

    def test_path_traversal_detection(self):
        """Test path traversal attack detection."""
        # Arrange
        malicious_path = "../../../etc/passwd"

        # Act & Assert
        with pytest.raises(ValueError) as exc_info:
            validate_and_sanitize_file_path(malicious_path)

        assert "Path traversal detected" in str(exc_info.value)

    def test_non_yaml_file_rejection(self):
        """Test rejection of non-YAML files."""
        # Arrange
        non_yaml_path = "README.md"

        # Act & Assert
        with pytest.raises(ValueError) as exc_info:
            validate_and_sanitize_file_path(non_yaml_path)

        assert "File must be a YAML file" in str(exc_info.value)

    def test_invalid_file_path(self):
        """Test invalid file path handling."""
        # Arrange
        invalid_path = "/nonexistent/path/with/null\0characters"

        # Act & Assert
        with pytest.raises(ValueError) as exc_info:
            validate_and_sanitize_file_path(invalid_path)

        assert "Invalid file path" in str(exc_info.value)


class TestValidateYamlSyntax:
    """Test cases for YAML syntax validation."""

    def test_valid_yaml_syntax(self):
        """Test valid YAML syntax."""
        # Arrange
        with tempfile.NamedTemporaryFile(mode="w", suffix=".yml", delete=False) as f:
            yaml.dump({"test": "value", "number": 42}, f)
            temp_file = Path(f.name)

        try:
            # Act
            is_valid, error, content = validate_yaml_syntax(temp_file)

            # Assert
            assert is_valid is True
            assert error == ""
            assert content == {"test": "value", "number": 42}
        finally:
            os.unlink(temp_file)

    def test_invalid_yaml_syntax(self):
        """Test invalid YAML syntax."""
        # Arrange
        with tempfile.NamedTemporaryFile(mode="w", suffix=".yml", delete=False) as f:
            f.write("invalid: yaml: content: [")
            temp_file = Path(f.name)

        try:
            # Act
            is_valid, error, content = validate_yaml_syntax(temp_file)

            # Assert
            assert is_valid is False
            assert "YAML syntax error" in error
            assert content == {}
        finally:
            os.unlink(temp_file)

    def test_nonexistent_file(self):
        """Test handling of nonexistent file."""
        # Arrange
        nonexistent_file = Path("nonexistent_file.yml")

        # Act
        is_valid, error, content = validate_yaml_syntax(nonexistent_file)

        # Assert
        assert is_valid is False
        assert "File read error" in error
        assert content == {}


class TestValidateSchemaStructure:
    """Test cases for schema structure validation."""

    def test_valid_schema_structure(self):
        """Test valid schema structure."""
        # Arrange
        valid_schema = {
            "columns": {
                "id": {"type": "string", "required": True},
                "name": {"type": "string", "required": False},
            },
            "min_columns": 2,  # Must equal actual column count in strict mode
            "max_columns": 2,  # Must equal actual column count in strict mode
            "strict": True,
        }

        # Act
        errors = validate_schema_structure(valid_schema, Path("test.yml"))

        # Assert
        assert errors == []

    def test_missing_required_fields(self):
        """Test missing required fields."""
        # Arrange
        invalid_schema = {
            "columns": {
                "id": {"type": "string"}
                # Missing required field
            }
            # Missing min_columns, max_columns
        }

        # Act
        errors = validate_schema_structure(invalid_schema, Path("test.yml"))

        # Assert
        assert len(errors) == 3  # min_columns, max_columns, and required field
        assert any("Missing required field: 'min_columns'" in error for error in errors)
        assert any("Missing required field: 'max_columns'" in error for error in errors)
        assert any(
            "Column 'id' missing required field: 'required'" in error
            for error in errors
        )

    def test_missing_columns_field(self):
        """Test missing columns field."""
        # Arrange
        invalid_schema = {
            "min_columns": 1,
            "max_columns": 1,
            # Missing columns
        }

        # Act
        errors = validate_schema_structure(invalid_schema, Path("test.yml"))

        # Assert
        assert len(errors) == 1
        assert "Missing required field: 'columns'" in errors[0]

    def test_invalid_column_definition(self):
        """Test invalid column definition."""
        # Arrange
        invalid_schema = {
            "columns": {
                "id": "not_a_dict",  # Should be a dictionary
                "name": {
                    "type": "string"
                    # Missing required field
                },
            },
            "min_columns": 2,
            "max_columns": 2,
        }

        # Act
        errors = validate_schema_structure(invalid_schema, Path("test.yml"))

        # Assert
        assert len(errors) >= 2
        assert any(
            "Column 'id' definition must be a dictionary" in error for error in errors
        )
        assert any(
            "Column 'name' missing required field: 'required'" in error
            for error in errors
        )

    def test_invalid_column_type(self):
        """Test invalid column type."""
        # Arrange
        invalid_schema = {
            "columns": {"id": {"type": "invalid_type", "required": True}},
            "min_columns": 1,
            "max_columns": 1,
        }

        # Act
        errors = validate_schema_structure(invalid_schema, Path("test.yml"))

        # Assert
        assert len(errors) == 1
        assert "Column 'id' has invalid type 'invalid_type'" in errors[0]

    def test_invalid_required_field_type(self):
        """Test invalid required field type."""
        # Arrange
        invalid_schema = {
            "columns": {"id": {"type": "string", "required": "not_a_boolean"}},
            "min_columns": 1,
            "max_columns": 1,
        }

        # Act
        errors = validate_schema_structure(invalid_schema, Path("test.yml"))

        # Assert
        assert len(errors) == 1
        assert "Column 'id' 'required' field must be a boolean" in errors[0]

    def test_invalid_min_max_columns(self):
        """Test invalid min/max columns values."""
        # Arrange
        invalid_schema = {
            "columns": {"id": {"type": "string", "required": True}},
            "min_columns": -1,  # Invalid
            "max_columns": "not_a_number",  # Invalid
        }

        # Act
        errors = validate_schema_structure(invalid_schema, Path("test.yml"))

        # Assert
        assert len(errors) == 2
        assert any(
            "'min_columns' must be a non-negative integer" in error for error in errors
        )
        assert any(
            "'max_columns' must be a non-negative integer" in error for error in errors
        )

    def test_min_columns_greater_than_max_columns(self):
        """Test min_columns greater than max_columns."""
        # Arrange
        invalid_schema = {
            "columns": {"id": {"type": "string", "required": True}},
            "min_columns": 5,
            "max_columns": 3,
        }

        # Act
        errors = validate_schema_structure(invalid_schema, Path("test.yml"))

        # Assert
        assert len(errors) == 2  # min > max and column count < min_columns
        assert any(
            "'min_columns' cannot be greater than 'max_columns'" in error
            for error in errors
        )
        assert any(
            "Column count (1) is less than min_columns (5)" in error for error in errors
        )

    def test_column_count_validation(self):
        """Test column count validation against min/max constraints."""
        # Arrange
        invalid_schema = {
            "columns": {
                "id": {"type": "string", "required": True},
                "name": {"type": "string", "required": True},
            },
            "min_columns": 3,  # More than actual columns
            "max_columns": 1,  # Less than actual columns
        }

        # Act
        errors = validate_schema_structure(invalid_schema, Path("test.yml"))

        # Assert
        assert len(errors) == 3  # min > max, column count < min, column count > max
        assert any(
            "'min_columns' cannot be greater than 'max_columns'" in error
            for error in errors
        )
        assert any(
            "Column count (2) is less than min_columns (3)" in error for error in errors
        )
        assert any(
            "Column count (2) is greater than max_columns (1)" in error
            for error in errors
        )

    def test_strict_mode_validation(self):
        """Test strict mode validation."""
        # Arrange
        invalid_schema = {
            "columns": {
                "id": {"type": "string", "required": True},
                "name": {"type": "string", "required": True},
            },
            "min_columns": 1,  # Different from actual count
            "max_columns": 3,  # Different from actual count
            "strict": True,
        }

        # Act
        errors = validate_schema_structure(invalid_schema, Path("test.yml"))

        # Assert
        assert len(errors) == 2
        assert any(
            "In strict mode, min_columns (1) should equal max_columns (3)" in error
            for error in errors
        )
        assert any(
            "In strict mode, actual column count (2) should equal min_columns (1)"
            in error
            for error in errors
        )

    def test_invalid_strict_field_type(self):
        """Test invalid strict field type."""
        # Arrange
        invalid_schema = {
            "columns": {"id": {"type": "string", "required": True}},
            "min_columns": 1,
            "max_columns": 1,
            "strict": "not_a_boolean",
        }

        # Act
        errors = validate_schema_structure(invalid_schema, Path("test.yml"))

        # Assert
        assert len(errors) == 1
        assert "'strict' field must be a boolean" in errors[0]

    def test_nullable_field_ignored(self):
        """Test that nullable field is ignored (not validated)."""
        # Arrange
        schema_with_nullable = {
            "columns": {
                "id": {
                    "type": "string",
                    "required": True,
                    "nullable": "invalid_value",  # This should be ignored
                }
            },
            "min_columns": 1,
            "max_columns": 1,
        }

        # Act
        errors = validate_schema_structure(schema_with_nullable, Path("test.yml"))

        # Assert
        assert errors == []  # No errors because nullable is ignored

    def test_schema_without_nullable_field(self):
        """Test schema without nullable field (should be valid)."""
        # Arrange
        schema_without_nullable = {
            "columns": {
                "id": {
                    "type": "string",
                    "required": True,
                    # No nullable field
                }
            },
            "min_columns": 1,
            "max_columns": 1,
        }

        # Act
        errors = validate_schema_structure(schema_without_nullable, Path("test.yml"))

        # Assert
        assert errors == []  # Should be valid without nullable field


class TestValidateSchemaFileContent:
    """Test cases for complete schema file content validation."""

    def test_valid_schema_file(self):
        """Test valid schema file."""
        # Arrange
        valid_schema = {
            "columns": {
                "id": {"type": "string", "required": True},
                "name": {"type": "string", "required": False},
            },
            "min_columns": 2,  # Must equal actual column count in strict mode
            "max_columns": 2,  # Must equal actual column count in strict mode
            "strict": True,
        }

        with tempfile.NamedTemporaryFile(mode="w", suffix=".yml", delete=False) as f:
            yaml.dump(valid_schema, f)
            temp_file = Path(f.name)

        try:
            # Act
            errors = validate_schema_file_content(temp_file)

            # Assert
            assert errors == []
        finally:
            os.unlink(temp_file)

    def test_nonexistent_schema_file(self):
        """Test nonexistent schema file."""
        # Arrange
        nonexistent_file = Path("nonexistent_schema.yml")

        # Act
        errors = validate_schema_file_content(nonexistent_file)

        # Assert
        assert len(errors) == 1
        assert "Schema file does not exist" in errors[0]

    def test_invalid_yaml_schema_file(self):
        """Test schema file with invalid YAML."""
        # Arrange
        with tempfile.NamedTemporaryFile(mode="w", suffix=".yml", delete=False) as f:
            f.write("invalid: yaml: content: [")
            temp_file = Path(f.name)

        try:
            # Act
            errors = validate_schema_file_content(temp_file)

            # Assert
            assert len(errors) == 1
            assert "YAML syntax error" in errors[0]
        finally:
            os.unlink(temp_file)

    def test_invalid_schema_structure(self):
        """Test schema file with invalid structure."""
        # Arrange
        invalid_schema = {
            "columns": {"id": {"type": "invalid_type", "required": True}},
            "min_columns": -1,
            "max_columns": "not_a_number",
        }

        with tempfile.NamedTemporaryFile(mode="w", suffix=".yml", delete=False) as f:
            yaml.dump(invalid_schema, f)
            temp_file = Path(f.name)

        try:
            # Act
            errors = validate_schema_file_content(temp_file)

            # Assert
            assert len(errors) >= 3  # Multiple validation errors
            assert any(
                "Column 'id' has invalid type 'invalid_type'" in error
                for error in errors
            )
            assert any(
                "'min_columns' must be a non-negative integer" in error
                for error in errors
            )
            assert any(
                "'max_columns' must be a non-negative integer" in error
                for error in errors
            )
        finally:
            os.unlink(temp_file)


class TestGetSchemaFilesToValidate:
    """Test cases for getting schema files to validate."""

    def test_file_mode_valid_path(self):
        """Test file mode with valid path."""
        # Arrange
        valid_path = "dags/core/core_visit/schemas/core/visit.yml"

        # Act
        files = get_schema_files_to_validate("file", valid_path)

        # Assert
        assert len(files) == 1
        assert files[0][0].name == "visit.yml"
        assert files[0][1] == "A"

    def test_file_mode_invalid_path(self):
        """Test file mode with invalid path."""
        # Arrange
        invalid_path = "../../../etc/passwd"

        # Act
        files = get_schema_files_to_validate("file", invalid_path)

        # Assert
        assert files == []

    @patch("scripts.ci_cd.validate_core_model_schema_content.find_core_model_dags")
    def test_all_files_mode(self, mock_find_dags):
        """Test all files mode."""
        # Arrange
        mock_dag_dir = Mock()
        mock_dag_dir.name = "test_dag"

        # Mock the path operations
        mock_declaration_file = Mock()
        mock_schema_file = Mock()
        mock_dag_dir.__truediv__ = Mock(return_value=mock_declaration_file)
        mock_schema_file.__truediv__ = Mock(return_value=mock_schema_file)
        mock_declaration_file.__truediv__ = Mock(return_value=mock_schema_file)

        mock_find_dags.return_value = [mock_dag_dir]

        with patch(
            "scripts.ci_cd.validate_core_model_schema_content.extract_tables_from_declaration"
        ) as mock_extract:
            mock_extract.return_value = ("test_dag", "core", {"visit"})

            # Act
            files = get_schema_files_to_validate("all_files", None)

            # Assert
            assert len(files) == 1
            assert files[0][1] == "A"

    @patch("scripts.ci_cd.validate_core_model_schema_content.GitService")
    def test_branch_mode(self, mock_git_service):
        """Test branch mode."""
        # Arrange
        mock_git_instance = Mock()
        mock_git_service.return_value = mock_git_instance
        mock_git_instance.get_modified_files_from_diff.return_value = {
            "dags/core/test_dag/schemas/core/visit.yml": "M"
        }

        # Mock GitService.UPSERT_STATUS_CODES
        mock_git_service.UPSERT_STATUS_CODES = ["M", "A"]

        # Act
        files = get_schema_files_to_validate("branch", "test_branch")

        # Assert
        assert len(files) == 1
        assert files[0][0].name == "visit.yml"
        assert files[0][1] == "M"


class TestValidateCoreModelSchemaContent:
    """Test cases for the main validation function."""

    @patch(
        "scripts.ci_cd.validate_core_model_schema_content.get_schema_files_to_validate"
    )
    @patch(
        "scripts.ci_cd.validate_core_model_schema_content.validate_schema_file_content"
    )
    def test_validate_core_model_schema_content_success(
        self, mock_validate, mock_get_files
    ):
        """Test successful validation."""
        # Arrange
        mock_file = Path("test_schema.yml")
        mock_get_files.return_value = [(mock_file, "A")]
        mock_validate.return_value = []

        # Act
        result = validate_core_model_schema_content("all_files", None, False)

        # Assert
        assert result is True
        mock_get_files.assert_called_once_with("all_files", None)
        mock_validate.assert_called_once_with(mock_file)

    @patch(
        "scripts.ci_cd.validate_core_model_schema_content.get_schema_files_to_validate"
    )
    @patch(
        "scripts.ci_cd.validate_core_model_schema_content.validate_schema_file_content"
    )
    def test_validate_core_model_schema_content_failure(
        self, mock_validate, mock_get_files
    ):
        """Test validation failure."""
        # Arrange
        mock_file = Path("test_schema.yml")
        mock_get_files.return_value = [(mock_file, "A")]
        mock_validate.return_value = ["Test validation error"]

        # Act
        result = validate_core_model_schema_content("all_files", None, False)

        # Assert
        assert result is False
        mock_get_files.assert_called_once_with("all_files", None)
        mock_validate.assert_called_once_with(mock_file)

    @patch(
        "scripts.ci_cd.validate_core_model_schema_content.get_schema_files_to_validate"
    )
    def test_validate_core_model_schema_content_no_files(self, mock_get_files):
        """Test validation with no files to validate."""
        # Arrange
        mock_get_files.return_value = []

        # Act
        result = validate_core_model_schema_content("branch", "test_branch", False)

        # Assert
        assert result is True  # Should pass when no files to validate
        mock_get_files.assert_called_once_with("branch", "test_branch")


# Pytest markers
pytestmark = [pytest.mark.unit, pytest.mark.ci_cd, pytest.mark.schema_validation]
