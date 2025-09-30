#!/usr/bin/env python3
"""
Unit tests for the core model schema existence validation script.
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import patch, Mock, mock_open

# Import the validation functions
sys.path.append(".")
try:
    from scripts.ci_cd.validate_core_model_schemas import (
        validate_and_sanitize_file_path,
        find_core_model_dags,
        extract_tables_from_declaration,
        get_schema_files_to_validate,
        validate_core_model_schemas,
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


class TestFindCoreModelDags:
    """Test cases for finding core model DAGs."""

    @patch("scripts.ci_cd.validate_core_model_schemas.Path")
    def test_find_core_model_dags_success(self, mock_path):
        """Test successful finding of core model DAGs."""
        # Arrange
        mock_core_dir = Mock()
        mock_dag_dir = Mock()
        mock_dag_dir.name = "core_visit"
        mock_dag_dir.is_dir.return_value = True

        mock_declaration_file = Mock()
        mock_declaration_file.exists.return_value = True
        mock_dag_dir.__truediv__ = Mock(return_value=mock_declaration_file)

        mock_core_dir.iterdir.return_value = [mock_dag_dir]
        mock_core_dir.exists.return_value = True
        mock_path.return_value = mock_core_dir

        # Act
        result = find_core_model_dags()

        # Assert
        assert len(result) == 1
        assert result[0] == mock_dag_dir

    @patch("scripts.ci_cd.validate_core_model_schemas.Path")
    def test_find_core_model_dags_no_core_dir(self, mock_path):
        """Test when core directory doesn't exist."""
        # Arrange
        mock_core_dir = Mock()
        mock_core_dir.exists.return_value = False
        mock_path.return_value = mock_core_dir

        # Act
        result = find_core_model_dags()

        # Assert
        assert result == []

    @patch("scripts.ci_cd.validate_core_model_schemas.Path")
    def test_find_core_model_dags_no_declaration_file(self, mock_path):
        """Test when declaration file doesn't exist."""
        # Arrange
        mock_core_dir = Mock()
        mock_dag_dir = Mock()
        mock_dag_dir.name = "core_visit"
        mock_dag_dir.is_dir.return_value = True

        mock_declaration_file = Mock()
        mock_declaration_file.exists.return_value = False
        mock_dag_dir.__truediv__ = Mock(return_value=mock_declaration_file)

        mock_core_dir.iterdir.return_value = [mock_dag_dir]
        mock_core_dir.exists.return_value = True
        mock_path.return_value = mock_core_dir

        # Act
        result = find_core_model_dags()

        # Assert
        assert result == []


class TestExtractTablesFromDeclaration:
    """Test cases for extracting tables from declaration files."""

    def test_extract_tables_success(self):
        """Test successful table extraction."""
        # Arrange
        declaration_content = {
            "dag": {"name": "core_visit"},
            "workflow": {"layer": "core", "tables_customization": {"visit": {}}},
        }

        mock_file = Mock()
        mock_file.read_text.return_value = "yaml_content"

        with patch(
            "scripts.ci_cd.validate_core_model_schemas.yaml.safe_load"
        ) as mock_yaml_load, patch(
            "builtins.open", mock_open(read_data="yaml_content")
        ):
            mock_yaml_load.return_value = declaration_content

            # Act
            dag_name, layer, table_names = extract_tables_from_declaration(mock_file)

            # Assert
            assert dag_name == "core_visit"
            assert layer == "core"
            assert table_names == {"visit"}

    def test_extract_tables_missing_dag_name(self):
        """Test extraction with missing DAG name."""
        # Arrange
        declaration_content = {
            "workflow": {"layer": "core", "tables_customization": {"visit": {}}}
        }

        mock_file = Mock()

        with patch(
            "scripts.ci_cd.validate_core_model_schemas.yaml.safe_load"
        ) as mock_yaml_load, patch(
            "builtins.open", mock_open(read_data="yaml_content")
        ):
            mock_yaml_load.return_value = declaration_content

            # Act
            dag_name, layer, table_names = extract_tables_from_declaration(mock_file)

            # Assert
            assert dag_name == ""
            assert layer == "core"
            assert table_names == {"visit"}

    def test_extract_tables_missing_layer(self):
        """Test extraction with missing layer."""
        # Arrange
        declaration_content = {
            "dag": {"name": "core_visit"},
            "workflow": {"tables_customization": {"visit": {}}},
        }

        mock_file = Mock()

        with patch(
            "scripts.ci_cd.validate_core_model_schemas.yaml.safe_load"
        ) as mock_yaml_load, patch(
            "builtins.open", mock_open(read_data="yaml_content")
        ):
            mock_yaml_load.return_value = declaration_content

            # Act
            dag_name, layer, table_names = extract_tables_from_declaration(mock_file)

            # Assert
            assert dag_name == "core_visit"
            assert layer == ""
            assert table_names == {"visit"}

    def test_extract_tables_missing_tables_customization(self):
        """Test extraction with missing tables_customization."""
        # Arrange
        declaration_content = {
            "dag": {"name": "core_visit"},
            "workflow": {"layer": "core"},
        }

        mock_file = Mock()

        with patch(
            "scripts.ci_cd.validate_core_model_schemas.yaml.safe_load"
        ) as mock_yaml_load, patch(
            "builtins.open", mock_open(read_data="yaml_content")
        ):
            mock_yaml_load.return_value = declaration_content

            # Act
            dag_name, layer, table_names = extract_tables_from_declaration(mock_file)

            # Assert
            assert dag_name == "core_visit"
            assert layer == "core"
            assert table_names == set()

    def test_extract_tables_yaml_error(self):
        """Test extraction with YAML parsing error."""
        # Arrange
        mock_file = Mock()
        mock_file.read_text.side_effect = Exception("YAML parsing error")

        # Act
        dag_name, layer, table_names = extract_tables_from_declaration(mock_file)

        # Assert
        assert dag_name == ""
        assert layer == ""
        assert table_names == set()


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

    @patch("scripts.ci_cd.validate_core_model_schemas.find_core_model_dags")
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
            "scripts.ci_cd.validate_core_model_schemas.extract_tables_from_declaration"
        ) as mock_extract:
            mock_extract.return_value = ("test_dag", "core", {"visit"})

            # Act
            files = get_schema_files_to_validate("all_files", None)

            # Assert
            assert len(files) == 1
            assert files[0][1] == "A"

    @patch("scripts.ci_cd.validate_core_model_schemas.GitService")
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

    @patch("scripts.ci_cd.validate_core_model_schemas.GitService")
    def test_branch_mode_with_declaration_file_change(self, mock_git_service):
        """Test branch mode with declaration file change."""
        # Arrange
        mock_git_instance = Mock()
        mock_git_service.return_value = mock_git_instance
        mock_git_instance.get_modified_files_from_diff.return_value = {
            "dags/core/test_dag/test_dag_declaration.yml": "M"
        }

        # Mock GitService.UPSERT_STATUS_CODES
        mock_git_service.UPSERT_STATUS_CODES = ["M", "A"]

        with patch(
            "scripts.ci_cd.validate_core_model_schemas.extract_tables_from_declaration"
        ) as mock_extract:
            mock_extract.return_value = ("test_dag", "core", {"visit"})

            # Act
            files = get_schema_files_to_validate("branch", "test_branch")

            # Assert
            assert len(files) == 1
            assert files[0][0].name == "visit.yml"
            assert files[0][1] == "M"


class TestValidateCoreModelSchemas:
    """Test cases for the main validation function."""

    @patch("scripts.ci_cd.validate_core_model_schemas.get_schema_files_to_validate")
    def test_validate_core_model_schemas_success(self, mock_get_files):
        """Test successful validation."""
        # Arrange
        mock_file = Mock()
        mock_file.exists.return_value = True
        mock_file.name = "test_schema.yml"
        mock_get_files.return_value = [(mock_file, "A")]

        # Act
        result = validate_core_model_schemas("all_files", None, False)

        # Assert
        assert result is True
        mock_get_files.assert_called_once_with("all_files", None)

    @patch("scripts.ci_cd.validate_core_model_schemas.get_schema_files_to_validate")
    def test_validate_core_model_schemas_missing_file(self, mock_get_files):
        """Test validation with missing schema file."""
        # Arrange
        mock_file = Mock()
        mock_file.exists.return_value = False
        mock_file.name = "missing_schema.yml"
        mock_get_files.return_value = [(mock_file, "A")]

        # Act
        result = validate_core_model_schemas("all_files", None, False)

        # Assert
        assert result is False
        mock_get_files.assert_called_once_with("all_files", None)

    @patch("scripts.ci_cd.validate_core_model_schemas.get_schema_files_to_validate")
    def test_validate_core_model_schemas_no_files(self, mock_get_files):
        """Test validation with no files to validate."""
        # Arrange
        mock_get_files.return_value = []

        # Act
        result = validate_core_model_schemas("branch", "test_branch", False)

        # Assert
        assert result is True  # Should pass when no files to validate
        mock_get_files.assert_called_once_with("branch", "test_branch")

    @patch("scripts.ci_cd.validate_core_model_schemas.get_schema_files_to_validate")
    def test_validate_core_model_schemas_verbose_mode(self, mock_get_files):
        """Test validation in verbose mode."""
        # Arrange
        mock_file = Mock()
        mock_file.exists.return_value = True
        mock_file.name = "test_schema.yml"
        mock_get_files.return_value = [(mock_file, "A")]

        # Act
        result = validate_core_model_schemas("all_files", None, True)

        # Assert
        assert result is True
        mock_get_files.assert_called_once_with("all_files", None)


# Pytest markers
pytestmark = [pytest.mark.unit, pytest.mark.ci_cd, pytest.mark.schema_validation]
