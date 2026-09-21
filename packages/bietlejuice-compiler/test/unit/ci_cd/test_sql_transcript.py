#!/usr/bin/env python3
"""
Unit tests for the SQL transpiler script.
"""

import os
import sys
import tempfile
from unittest.mock import Mock, patch

import pytest

# Import the transpiler classes
sys.path.append(".")
try:
    from scripts.ci_cd.sql_transcript import SQLTranspiler, SQLTranspilerRunner, main
except ImportError:
    pass


class TestSQLTranspilerCustomReplacements:
    """Test cases for custom SQL replacements."""

    def test_replace_current_date_function_call(self):
        """Test replacement of CURRENT_DATE() function call."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        sql_content = "SELECT * FROM table WHERE date = CURRENT_DATE()"

        # Act
        result, count = transpiler.apply_custom_replacements(sql_content)

        # Assert
        assert "DATE('{load_start_date}')" in result
        assert "CURRENT_DATE()" not in result
        assert count == 1

    def test_replace_current_date_without_parentheses(self):
        """Test replacement of CURRENT_DATE without parentheses."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        sql_content = "SELECT * FROM table WHERE date = CURRENT_DATE"

        # Act
        result, count = transpiler.apply_custom_replacements(sql_content)

        # Assert
        assert "DATE('{load_start_date}')" in result
        assert count == 1

    def test_replace_multiple_current_date_occurrences(self):
        """Test replacement of multiple CURRENT_DATE occurrences."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        sql_content = """
        SELECT * FROM table
        WHERE start_date = CURRENT_DATE()
        AND end_date = CURRENT_DATE
        """

        # Act
        result, count = transpiler.apply_custom_replacements(sql_content)

        # Assert
        assert result.count("DATE('{load_start_date}')") == 2
        assert count == 2

    def test_replace_current_date_case_insensitive(self):
        """Test replacement is case insensitive."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        sql_content = "SELECT current_date, CURRENT_DATE(), Current_Date"

        # Act
        result, count = transpiler.apply_custom_replacements(sql_content)

        # Assert
        assert count == 3
        assert (
            "current_date" not in result.lower()
            or "DATE('{load_start_date}')" in result
        )

    def test_no_replacements_needed(self):
        """Test when no replacements are needed."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        sql_content = "SELECT * FROM table WHERE date = '2024-01-01'"

        # Act
        result, count = transpiler.apply_custom_replacements(sql_content)

        # Assert
        assert result == sql_content
        assert count == 0


class TestSQLTranspilerTranspileSQL:
    """Test cases for SQL transpilation."""

    @patch("scripts.ci_cd.sql_transcript.transpile")
    def test_successful_transpilation(self, mock_transpile):
        """Test successful SQL transpilation."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        original_sql = "SELECT * FROM table"
        transpiled_sql = "SELECT\n  *\nFROM table"
        mock_transpile.return_value = [transpiled_sql]

        # Act
        result, error = transpiler.transpile_sql(original_sql)

        # Assert
        assert result is not None
        assert error is None
        assert transpiled_sql in result
        mock_transpile.assert_called_once_with(
            original_sql, read="trino", write="databricks", pretty=True
        )

    @patch("scripts.ci_cd.sql_transcript.transpile")
    def test_transpilation_with_multiple_statements(self, mock_transpile):
        """Test transpilation with multiple SQL statements."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        original_sql = "SELECT * FROM table1; SELECT * FROM table2"
        mock_transpile.return_value = ["SELECT * FROM table1", "SELECT * FROM table2"]

        # Act
        result, error = transpiler.transpile_sql(original_sql)

        # Assert
        assert result is not None
        assert error is None
        assert ";\n" in result
        assert "table1" in result
        assert "table2" in result

    @patch("scripts.ci_cd.sql_transcript.transpile")
    def test_transpilation_empty_result(self, mock_transpile):
        """Test transpilation with empty result."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        original_sql = "SELECT * FROM table"
        mock_transpile.return_value = []

        # Act
        result, error = transpiler.transpile_sql(original_sql)

        # Assert
        assert result is None
        assert "empty result" in error.lower()

    @patch("scripts.ci_cd.sql_transcript.transpile")
    def test_transpilation_exception(self, mock_transpile):
        """Test transpilation with exception."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        original_sql = "INVALID SQL"
        mock_transpile.side_effect = Exception("Parse error")

        # Act
        result, error = transpiler.transpile_sql(original_sql)

        # Assert
        assert result is None
        assert error is not None
        assert "Transpilation error" in error

    @patch("scripts.ci_cd.sql_transcript.transpile")
    def test_transpilation_preserves_trailing_newline(self, mock_transpile):
        """Test that transpilation preserves trailing newlines."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        original_sql = "SELECT * FROM table\n"
        mock_transpile.return_value = ["SELECT * FROM table"]

        # Act
        result, _ = transpiler.transpile_sql(original_sql)

        # Assert
        assert result is not None
        assert result.endswith("\n")


class TestSQLTranspilerTranspileFile:
    """Test cases for file transpilation."""

    @patch("scripts.ci_cd.sql_transcript.SQLTranspiler.transpile_sql")
    def test_successful_file_transpilation(self, mock_transpile_sql):
        """Test successful file transpilation."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        original_content = "SELECT * FROM table"
        transpiled_content = "SELECT\n  *\nFROM table"
        mock_transpile_sql.return_value = (transpiled_content, None)

        with tempfile.NamedTemporaryFile(mode="w", suffix=".sql", delete=False) as f:
            f.write(original_content)
            temp_file = f.name

        try:
            # Act
            result = transpiler.transpile_file(temp_file)

            # Assert
            assert result is True
            assert transpiler.success_count == 1
            assert transpiler.error_count == 0

            # Verify file content was updated
            with open(temp_file) as f:
                content = f.read()
                assert content == transpiled_content
        finally:
            os.unlink(temp_file)

    @patch("scripts.ci_cd.sql_transcript.SQLTranspiler.transpile_sql")
    def test_file_transpilation_dry_run(self, mock_transpile_sql):
        """Test file transpilation in dry-run mode."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=True)
        original_content = "SELECT * FROM table"
        transpiled_content = "SELECT\n  *\nFROM table"
        mock_transpile_sql.return_value = (transpiled_content, None)

        with tempfile.NamedTemporaryFile(mode="w", suffix=".sql", delete=False) as f:
            f.write(original_content)
            temp_file = f.name

        try:
            # Act
            result = transpiler.transpile_file(temp_file)

            # Assert
            assert result is True
            assert transpiler.success_count == 1

            # Verify file content was NOT updated
            with open(temp_file) as f:
                content = f.read()
                assert content == original_content
        finally:
            os.unlink(temp_file)

    @patch("scripts.ci_cd.sql_transcript.SQLTranspiler.transpile_sql")
    def test_file_transpilation_no_changes(self, mock_transpile_sql):
        """Test file transpilation when no changes are needed."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        original_content = "SELECT * FROM table"
        mock_transpile_sql.return_value = (original_content, None)  # Same content

        with tempfile.NamedTemporaryFile(mode="w", suffix=".sql", delete=False) as f:
            f.write(original_content)
            temp_file = f.name

        try:
            # Act
            result = transpiler.transpile_file(temp_file)

            # Assert
            assert result is True
            assert transpiler.unchanged_count == 1
            assert transpiler.success_count == 0
        finally:
            os.unlink(temp_file)

    def test_file_transpilation_empty_file(self):
        """Test transpilation of empty file."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)

        with tempfile.NamedTemporaryFile(mode="w", suffix=".sql", delete=False) as f:
            f.write("")
            temp_file = f.name

        try:
            # Act
            result = transpiler.transpile_file(temp_file)

            # Assert
            assert result is True
            assert transpiler.unchanged_count == 1
        finally:
            os.unlink(temp_file)

    @patch("scripts.ci_cd.sql_transcript.SQLTranspiler.transpile_sql")
    def test_file_transpilation_error(self, mock_transpile_sql):
        """Test file transpilation with error."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        original_content = "INVALID SQL"
        mock_transpile_sql.return_value = (None, "Transpilation error")

        with tempfile.NamedTemporaryFile(mode="w", suffix=".sql", delete=False) as f:
            f.write(original_content)
            temp_file = f.name

        try:
            # Act
            result = transpiler.transpile_file(temp_file)

            # Assert
            assert result is False
            assert transpiler.error_count == 1
            assert len(transpiler.errors) == 1
        finally:
            os.unlink(temp_file)

    def test_file_not_found(self):
        """Test transpilation of non-existent file."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        nonexistent_file = "/tmp/nonexistent_file_12345.sql"

        # Act
        result = transpiler.transpile_file(nonexistent_file)

        # Assert
        assert result is False
        assert transpiler.error_count == 1
        assert len(transpiler.errors) == 1


class TestSQLTranspilerSummary:
    """Test cases for summary printing."""

    def test_print_summary_success(self, capsys):
        """Test printing summary with successful transpilations."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        transpiler.success_count = 5
        transpiler.error_count = 0
        transpiler.unchanged_count = 2
        transpiler.current_date_replacements = 3

        # Act
        transpiler.print_summary()

        # Assert
        captured = capsys.readouterr()
        assert "Total files processed: 7" in captured.out
        assert "Successfully transpiled: 5" in captured.out
        assert "No changes needed: 2" in captured.out
        assert "Errors: 0" in captured.out
        assert "CURRENT_DATE" in captured.out

    def test_print_summary_with_errors(self, capsys):
        """Test printing summary with errors."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        transpiler.success_count = 3
        transpiler.error_count = 2
        transpiler.unchanged_count = 1
        transpiler.errors = [
            ("file1.sql", "Parse error"),
            ("file2.sql", "Invalid syntax"),
        ]

        # Act
        transpiler.print_summary()

        # Assert
        captured = capsys.readouterr()
        assert "Errors: 2" in captured.out
        assert "file1.sql" in captured.out
        assert "file2.sql" in captured.out
        assert "Parse error" in captured.out

    def test_print_summary_no_custom_replacements(self, capsys):
        """Test printing summary without custom replacements."""
        # Arrange
        transpiler = SQLTranspiler(dry_run=False)
        transpiler.success_count = 2
        transpiler.error_count = 0
        transpiler.unchanged_count = 0
        transpiler.current_date_replacements = 0

        # Act
        transpiler.print_summary()

        # Assert
        captured = capsys.readouterr()
        assert "Total files processed: 2" in captured.out
        assert "Custom Replacements" not in captured.out


class TestSQLTranspilerRunnerGitDiff:
    """Test cases for git diff mode."""

    @patch("scripts.ci_cd.sql_transcript.GitService")
    def test_get_sql_files_from_git_diff(self, mock_git_service):
        """Test getting SQL files from git diff."""
        # Arrange
        args = Mock()
        args.dry_run = False
        args.from_branch = "origin/master"
        args.to_branch = "HEAD"
        args.fetch = False

        mock_git_instance = Mock()
        mock_git_service.return_value = mock_git_instance
        mock_git_instance.get_modified_files_from_diff.return_value = {
            "dags/planning_and_performance/query1.sql": "A",
            "dags/planning_and_performance/query2.sql": "M",
            "dags/planning_and_performance/README.md": "A",
            "dags/planning_and_performance/query3.sql": "D",
        }
        mock_git_instance.NEW_OR_MODIFIED_FILE_STATUS = ["A", "M"]

        runner = SQLTranspilerRunner(args)

        # Act
        sql_files = runner.get_sql_files_from_git_diff()

        # Assert
        assert len(sql_files) == 2
        assert "dags/planning_and_performance/query1.sql" in sql_files
        assert "dags/planning_and_performance/query2.sql" in sql_files
        assert "dags/planning_and_performance/README.md" not in sql_files
        assert "dags/planning_and_performance/query3.sql" not in sql_files

    @patch("scripts.ci_cd.sql_transcript.GitService")
    def test_get_sql_files_with_fetch(self, mock_git_service):
        """Test getting SQL files with fetch enabled."""
        # Arrange
        args = Mock()
        args.dry_run = False
        args.from_branch = "origin/master"
        args.to_branch = "HEAD"
        args.fetch = True

        mock_git_instance = Mock()
        mock_git_service.return_value = mock_git_instance
        mock_git_instance.get_modified_files_from_diff.return_value = {}
        mock_git_instance.NEW_OR_MODIFIED_FILE_STATUS = ["A", "M"]

        runner = SQLTranspilerRunner(args)

        # Act
        sql_files = runner.get_sql_files_from_git_diff()

        # Assert
        mock_git_instance.fetch.assert_called_once_with("master")
        assert sql_files == []

    @patch("scripts.ci_cd.sql_transcript.GitService")
    def test_get_sql_files_not_in_planning_and_performance(self, mock_git_service):
        """Test that files NOT in planning_and_performance folder are filtered out."""
        # Arrange
        args = Mock()
        args.dry_run = False
        args.from_branch = "origin/master"
        args.to_branch = "HEAD"
        args.fetch = False

        mock_git_instance = Mock()
        mock_git_service.return_value = mock_git_instance
        mock_git_instance.get_modified_files_from_diff.return_value = {
            "dags/fintech/query1.sql": "A",
            "dags/support_and_service/query2.sql": "M",
            "dags/other_folder/query3.sql": "A",
        }
        mock_git_instance.NEW_OR_MODIFIED_FILE_STATUS = ["A", "M"]

        runner = SQLTranspilerRunner(args)

        # Act
        sql_files = runner.get_sql_files_from_git_diff()

        # Assert
        assert sql_files == []

    @patch("scripts.ci_cd.sql_transcript.GitService")
    def test_get_sql_files_mixed_folders(self, mock_git_service):
        """Test that only planning_and_performance files are returned when mixed with other folders."""
        # Arrange
        args = Mock()
        args.dry_run = False
        args.from_branch = "origin/master"
        args.to_branch = "HEAD"
        args.fetch = False

        mock_git_instance = Mock()
        mock_git_service.return_value = mock_git_instance
        mock_git_instance.get_modified_files_from_diff.return_value = {
            "dags/fintech/query1.sql": "A",
            "dags/planning_and_performance/query2.sql": "M",
            "dags/planning_and_performance/query3.sql": "A",
            "dags/other_folder/query4.sql": "M",
        }
        mock_git_instance.NEW_OR_MODIFIED_FILE_STATUS = ["A", "M"]

        runner = SQLTranspilerRunner(args)

        # Act
        sql_files = runner.get_sql_files_from_git_diff()

        # Assert
        assert len(sql_files) == 2
        assert "dags/planning_and_performance/query2.sql" in sql_files
        assert "dags/planning_and_performance/query3.sql" in sql_files
        assert "dags/fintech/query1.sql" not in sql_files
        assert "dags/other_folder/query4.sql" not in sql_files


class TestSQLTranspilerRunnerDirectory:
    """Test cases for directory mode."""

    def test_get_sql_files_from_directory(self):
        """Test getting SQL files from directory."""
        # Arrange
        args = Mock()
        args.dry_run = False

        # Create temporary directory structure
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create SQL files
            sql_file1 = os.path.join(temp_dir, "query1.sql")
            sql_file2 = os.path.join(temp_dir, "subdir", "query2.sql")
            os.makedirs(os.path.dirname(sql_file2), exist_ok=True)

            with open(sql_file1, "w") as f:
                f.write("SELECT 1")
            with open(sql_file2, "w") as f:
                f.write("SELECT 2")

            # Create non-SQL file
            other_file = os.path.join(temp_dir, "README.md")
            with open(other_file, "w") as f:
                f.write("# README")

            runner = SQLTranspilerRunner(args)

            # Act
            sql_files = runner.get_sql_files_from_directory(temp_dir)

            # Assert
            assert len(sql_files) == 2
            assert any(f.endswith("query1.sql") for f in sql_files)
            assert any(f.endswith("query2.sql") for f in sql_files)
            assert not any(f.endswith("README.md") for f in sql_files)


class TestSQLTranspilerRunnerRun:
    """Test cases for the main run method."""

    @patch("scripts.ci_cd.sql_transcript.GitService")
    @patch("scripts.ci_cd.sql_transcript.SQLTranspiler.transpile_file")
    def test_run_git_diff_mode_success(self, mock_transpile_file, mock_git_service):
        """Test run in git-diff mode with success."""
        # Arrange
        args = Mock()
        args.mode = "git-diff"
        args.from_branch = "origin/master"
        args.to_branch = "HEAD"
        args.fetch = False
        args.dry_run = False

        mock_git_instance = Mock()
        mock_git_service.return_value = mock_git_instance
        mock_git_instance.get_modified_files_from_diff.return_value = {
            "dags/planning_and_performance/test.sql": "A"
        }
        mock_git_instance.NEW_OR_MODIFIED_FILE_STATUS = ["A", "M"]

        mock_transpile_file.return_value = True

        runner = SQLTranspilerRunner(args)
        runner.transpiler.success_count = 1

        # Act
        exit_code = runner.run()

        # Assert
        assert exit_code == 0
        mock_transpile_file.assert_called_once_with(
            "dags/planning_and_performance/test.sql"
        )

    @patch("scripts.ci_cd.sql_transcript.GitService")
    def test_run_git_diff_mode_no_files(self, mock_git_service):
        """Test run in git-diff mode with no files."""
        # Arrange
        args = Mock()
        args.mode = "git-diff"
        args.from_branch = "origin/master"
        args.to_branch = "HEAD"
        args.fetch = False
        args.dry_run = False

        mock_git_instance = Mock()
        mock_git_service.return_value = mock_git_instance
        mock_git_instance.get_modified_files_from_diff.return_value = {}
        mock_git_instance.NEW_OR_MODIFIED_FILE_STATUS = ["A", "M"]

        runner = SQLTranspilerRunner(args)

        # Act
        exit_code = runner.run()

        # Assert
        assert exit_code == 0

    @patch("scripts.ci_cd.sql_transcript.GitService")
    def test_run_git_diff_mode_filtered_out(self, mock_git_service):
        """Test run in git-diff mode when files are filtered out (not in planning_and_performance)."""
        # Arrange
        args = Mock()
        args.mode = "git-diff"
        args.from_branch = "origin/master"
        args.to_branch = "HEAD"
        args.fetch = False
        args.dry_run = False

        mock_git_instance = Mock()
        mock_git_service.return_value = mock_git_instance
        # Files exist but NOT in planning_and_performance folder
        mock_git_instance.get_modified_files_from_diff.return_value = {
            "dags/fintech/query1.sql": "A",
            "dags/other/query2.sql": "M",
        }
        mock_git_instance.NEW_OR_MODIFIED_FILE_STATUS = ["A", "M"]

        runner = SQLTranspilerRunner(args)

        # Act
        exit_code = runner.run()

        # Assert
        assert exit_code == 0  # Should exit successfully when filtered out

    def test_run_single_file_mode_not_found(self):
        """Test run in single-file mode with non-existent file."""
        # Arrange
        args = Mock()
        args.mode = "single-file"
        args.file = "/tmp/nonexistent_file_12345.sql"
        args.dry_run = False

        runner = SQLTranspilerRunner(args)

        # Act
        exit_code = runner.run()

        # Assert
        assert exit_code == 1

    @patch("scripts.ci_cd.sql_transcript.SQLTranspiler.transpile_file")
    def test_run_single_file_mode_success(self, mock_transpile_file):
        """Test run in single-file mode with success."""
        # Arrange
        with tempfile.NamedTemporaryFile(mode="w", suffix=".sql", delete=False) as f:
            f.write("SELECT 1")
            temp_file = f.name

        try:
            args = Mock()
            args.mode = "single-file"
            args.file = temp_file
            args.dry_run = False

            mock_transpile_file.return_value = True

            runner = SQLTranspilerRunner(args)
            runner.transpiler.error_count = 0

            # Act
            exit_code = runner.run()

            # Assert
            assert exit_code == 0
            mock_transpile_file.assert_called_once_with(temp_file)
        finally:
            os.unlink(temp_file)

    def test_run_directory_mode_not_found(self):
        """Test run in directory mode with non-existent directory."""
        # Arrange
        args = Mock()
        args.mode = "directory"
        args.directory = "/tmp/nonexistent_directory_12345"
        args.dry_run = False

        runner = SQLTranspilerRunner(args)

        # Act
        exit_code = runner.run()

        # Assert
        assert exit_code == 1

    @patch("scripts.ci_cd.sql_transcript.SQLTranspiler.transpile_file")
    def test_run_directory_mode_success(self, mock_transpile_file):
        """Test run in directory mode with success."""
        # Arrange
        with tempfile.TemporaryDirectory() as temp_dir:
            sql_file = os.path.join(temp_dir, "query.sql")
            with open(sql_file, "w") as f:
                f.write("SELECT 1")

            args = Mock()
            args.mode = "directory"
            args.directory = temp_dir
            args.dry_run = False

            mock_transpile_file.return_value = True

            runner = SQLTranspilerRunner(args)
            runner.transpiler.error_count = 0

            # Act
            exit_code = runner.run()

            # Assert
            assert exit_code == 0
            assert mock_transpile_file.call_count >= 1

    @patch("scripts.ci_cd.sql_transcript.SQLTranspiler.transpile_file")
    def test_run_with_errors(self, mock_transpile_file):
        """Test run with transpilation errors."""
        # Arrange
        with tempfile.NamedTemporaryFile(mode="w", suffix=".sql", delete=False) as f:
            f.write("SELECT 1")
            temp_file = f.name

        try:
            args = Mock()
            args.mode = "single-file"
            args.file = temp_file
            args.dry_run = False

            mock_transpile_file.return_value = False

            runner = SQLTranspilerRunner(args)
            runner.transpiler.error_count = 1

            # Act
            exit_code = runner.run()

            # Assert
            assert exit_code == 1
        finally:
            os.unlink(temp_file)


class TestGitDiffDefaults:
    def test_defaults_to_the_resolved_ci_target(self, monkeypatch):
        monkeypatch.setenv("CI_PIPELINE_EVENT", "pull_request")
        monkeypatch.setenv("CI_COMMIT_BRANCH", "forno")
        monkeypatch.delenv("CI_COMMIT_TARGET_BRANCH", raising=False)
        captured = {}

        class FakeRunner:
            def __init__(self, args):
                captured["from_branch"] = args.from_branch
                captured["to_branch"] = args.to_branch

            def run(self):
                return 0

        monkeypatch.setattr(
            "scripts.ci_cd.sql_transcript.SQLTranspilerRunner", FakeRunner
        )
        monkeypatch.setattr(sys, "argv", ["sql_transcript.py", "--mode", "git-diff"])
        with pytest.raises(SystemExit) as exc:
            main()
        assert exc.value.code == 0
        assert captured["from_branch"] == "origin/forno"
        assert captured["to_branch"] == "HEAD"


# Pytest markers
pytestmark = [pytest.mark.unit, pytest.mark.ci_cd, pytest.mark.sql_transpiler]
