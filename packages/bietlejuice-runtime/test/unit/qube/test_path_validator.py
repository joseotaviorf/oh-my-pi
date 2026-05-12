"""
Unit tests for secure path validation.
"""

import os
from pathlib import Path
from unittest.mock import patch

import pytest

from bietlejuice.qube.jobs.common.path_validator import (
    PathSecurityError,
    _get_default_allowed_dirs,
    _is_path_in_allowed_dirs,
    validate_spec_path,
)


class TestValidateSpecPath:
    """Tests for validate_spec_path function."""

    def test_valid_relative_path_in_cwd(self, tmp_path):
        """Test validation of valid relative path within current directory."""
        # Create a test file
        test_file = tmp_path / "specs" / "test.yaml"
        test_file.parent.mkdir(parents=True, exist_ok=True)
        test_file.write_text("test: data")

        # Change to temp directory
        original_cwd = os.getcwd()
        try:
            os.chdir(tmp_path)
            result = validate_spec_path("specs/test.yaml")
            assert result.exists()
            assert result.name == "test.yaml"
            assert result.is_absolute()
        finally:
            os.chdir(original_cwd)

    def test_valid_absolute_path_in_allowed_dir(self, tmp_path):
        """Test validation of absolute path within allowed directory."""
        test_file = tmp_path / "test.yaml"
        test_file.write_text("test: data")

        allowed_dirs = [tmp_path]
        result = validate_spec_path(str(test_file), allowed_base_dirs=allowed_dirs)
        assert result == test_file

    def test_path_traversal_attempt_blocked(self, tmp_path):
        """Test that path traversal attempts are blocked."""
        # Create a file in parent directory
        parent_file = tmp_path.parent / "sensitive.yaml"
        parent_file.write_text("sensitive: data")

        # Create subdirectory to test from
        subdir = tmp_path / "subdir"
        subdir.mkdir(parents=True, exist_ok=True)

        # Try to access parent file via traversal
        original_cwd = os.getcwd()
        try:
            os.chdir(subdir)
            with pytest.raises(PathSecurityError, match="outside allowed directories"):
                validate_spec_path("../../sensitive.yaml")
        finally:
            os.chdir(original_cwd)

    def test_non_existent_file_fails(self, tmp_path):
        """Test that non-existent files are rejected when must_exist=True."""
        allowed_dirs = [tmp_path]
        with pytest.raises(FileNotFoundError):
            validate_spec_path(
                str(tmp_path / "nonexistent.yaml"),
                allowed_base_dirs=allowed_dirs,
                must_exist=True,
            )

    def test_non_existent_file_allowed_when_must_exist_false(self, tmp_path):
        """Test that non-existent files pass validation when must_exist=False."""
        # Parent directory must exist
        test_dir = tmp_path / "specs"
        test_dir.mkdir(parents=True, exist_ok=True)

        test_file = test_dir / "future.yaml"
        allowed_dirs = [tmp_path]

        result = validate_spec_path(
            str(test_file),
            allowed_base_dirs=allowed_dirs,
            must_exist=False,
        )
        assert result == test_file.resolve()

    def test_symlink_attack_prevented(self, tmp_path):
        """Test that symlink attacks are prevented through canonical resolution."""
        # Create a sensitive file outside allowed directory
        sensitive_dir = tmp_path / "sensitive"
        sensitive_dir.mkdir()
        sensitive_file = sensitive_dir / "secret.yaml"
        sensitive_file.write_text("secret: data")

        # Create allowed directory with symlink
        allowed_dir = tmp_path / "allowed"
        allowed_dir.mkdir()
        symlink = allowed_dir / "link.yaml"

        try:
            symlink.symlink_to(sensitive_file)
        except (OSError, NotImplementedError):
            # Skip test if symlinks not supported (e.g., Windows without admin)
            pytest.skip("Symlinks not supported on this system")

        # Symlink should resolve to actual path, which is outside allowed_dir
        with pytest.raises(PathSecurityError, match="outside allowed directories"):
            validate_spec_path(str(symlink), allowed_base_dirs=[allowed_dir])

    def test_absolute_path_outside_project_blocked(self, tmp_path):
        """Test that absolute paths outside project are blocked."""
        # Create file outside allowed directory
        outside_file = tmp_path / "outside" / "test.yaml"
        outside_file.parent.mkdir(parents=True, exist_ok=True)
        outside_file.write_text("test: data")

        # Only allow a different directory
        allowed_dir = tmp_path / "allowed"
        allowed_dir.mkdir()

        with pytest.raises(PathSecurityError, match="outside allowed directories"):
            validate_spec_path(str(outside_file), allowed_base_dirs=[allowed_dir])

    def test_empty_path_rejected(self):
        """Test that empty path string is rejected."""
        with pytest.raises(PathSecurityError, match="must be a non-empty string"):
            validate_spec_path("")

    def test_none_path_rejected(self):
        """Test that None path is rejected."""
        with pytest.raises(PathSecurityError, match="must be a non-empty string"):
            validate_spec_path(None)

    def test_parent_directory_must_exist_for_non_existent_file(self, tmp_path):
        """Test that parent directory must exist even when must_exist=False."""
        nonexistent_dir = tmp_path / "nonexistent_dir"
        test_file = nonexistent_dir / "test.yaml"

        with pytest.raises(FileNotFoundError, match="Spec file not found or invalid"):
            validate_spec_path(
                str(test_file),
                allowed_base_dirs=[tmp_path],
                must_exist=False,
            )

    def test_qube_specs_root_env_var(self, tmp_path):
        """Test that QUBE_SPECS_ROOT environment variable is respected."""
        test_file = tmp_path / "test.yaml"
        test_file.write_text("test: data")

        with patch.dict(os.environ, {"QUBE_SPECS_ROOT": str(tmp_path)}):
            # Should use QUBE_SPECS_ROOT from env var
            result = validate_spec_path(str(test_file))
            assert result == test_file

    def test_multiple_allowed_directories(self, tmp_path):
        """Test validation with multiple allowed base directories."""
        dir1 = tmp_path / "dir1"
        dir2 = tmp_path / "dir2"
        dir1.mkdir()
        dir2.mkdir()

        file1 = dir1 / "test1.yaml"
        file2 = dir2 / "test2.yaml"
        file1.write_text("test: 1")
        file2.write_text("test: 2")

        allowed_dirs = [dir1, dir2]

        # Both files should be allowed
        result1 = validate_spec_path(str(file1), allowed_base_dirs=allowed_dirs)
        result2 = validate_spec_path(str(file2), allowed_base_dirs=allowed_dirs)

        assert result1 == file1
        assert result2 == file2

    def test_nested_subdirectory_allowed(self, tmp_path):
        """Test that nested subdirectories within allowed dir are accepted."""
        nested_dir = tmp_path / "level1" / "level2" / "level3"
        nested_dir.mkdir(parents=True, exist_ok=True)
        test_file = nested_dir / "test.yaml"
        test_file.write_text("test: data")

        result = validate_spec_path(str(test_file), allowed_base_dirs=[tmp_path])
        assert result == test_file

    def test_case_sensitive_paths(self, tmp_path):
        """Test path validation is case-sensitive on case-sensitive filesystems."""
        test_file = tmp_path / "Test.yaml"
        test_file.write_text("test: data")

        # This should work
        result = validate_spec_path(str(test_file), allowed_base_dirs=[tmp_path])
        assert result == test_file

        # Note: On case-insensitive filesystems (macOS, Windows), Test.yaml == test.yaml
        # So we can't reliably test case mismatch rejection


class TestGetDefaultAllowedDirs:
    """Tests for _get_default_allowed_dirs function."""

    def test_includes_current_working_directory(self):
        """Test that CWD is always included in allowed directories."""
        allowed_dirs = _get_default_allowed_dirs()
        cwd = Path.cwd().resolve()
        assert cwd in allowed_dirs

    def test_includes_qube_specs_root_from_env(self, tmp_path):
        """Test that QUBE_SPECS_ROOT from env var is included."""
        with patch.dict(os.environ, {"QUBE_SPECS_ROOT": str(tmp_path)}):
            allowed_dirs = _get_default_allowed_dirs()
            assert tmp_path in allowed_dirs

    def test_ignores_invalid_qube_specs_root(self, tmp_path):
        """Test that invalid QUBE_SPECS_ROOT is ignored gracefully."""
        with patch.dict(os.environ, {"QUBE_SPECS_ROOT": "/nonexistent/path"}):
            # Should not raise error, just skip invalid path
            allowed_dirs = _get_default_allowed_dirs()
            assert Path("/nonexistent/path") not in allowed_dirs

    def test_includes_common_spec_directories(self, tmp_path):
        """Test that common spec directories are included if they exist."""
        original_cwd = os.getcwd()
        try:
            os.chdir(tmp_path)

            # Create common spec directories
            specs_dir = tmp_path / "specs"
            qube_specs_dir = tmp_path / "qube" / "specs"
            specs_dir.mkdir(parents=True, exist_ok=True)
            qube_specs_dir.mkdir(parents=True, exist_ok=True)

            allowed_dirs = _get_default_allowed_dirs()

            # Should include these directories
            assert tmp_path in allowed_dirs  # CWD
            assert specs_dir in allowed_dirs
            assert qube_specs_dir in allowed_dirs
        finally:
            os.chdir(original_cwd)


class TestIsPathInAllowedDirs:
    """Tests for _is_path_in_allowed_dirs function."""

    def test_path_within_allowed_dir(self, tmp_path):
        """Test that path within allowed directory returns True."""
        allowed_dir = tmp_path / "allowed"
        allowed_dir.mkdir()
        test_path = allowed_dir / "subdir" / "file.yaml"

        result = _is_path_in_allowed_dirs(test_path.resolve(), [allowed_dir.resolve()])
        assert result is True

    def test_path_outside_allowed_dir(self, tmp_path):
        """Test that path outside allowed directory returns False."""
        allowed_dir = tmp_path / "allowed"
        outside_dir = tmp_path / "outside"
        allowed_dir.mkdir()
        outside_dir.mkdir()

        test_path = outside_dir / "file.yaml"

        result = _is_path_in_allowed_dirs(test_path.resolve(), [allowed_dir.resolve()])
        assert result is False

    def test_exact_allowed_dir_path(self, tmp_path):
        """Test that the allowed directory itself is considered valid."""
        allowed_dir = tmp_path / "allowed"
        allowed_dir.mkdir()

        result = _is_path_in_allowed_dirs(
            allowed_dir.resolve(), [allowed_dir.resolve()]
        )
        assert result is True

    def test_multiple_allowed_dirs_first_match(self, tmp_path):
        """Test matching against first allowed directory."""
        dir1 = tmp_path / "dir1"
        dir2 = tmp_path / "dir2"
        dir1.mkdir()
        dir2.mkdir()

        test_path = dir1 / "file.yaml"
        allowed_dirs = [dir1.resolve(), dir2.resolve()]

        result = _is_path_in_allowed_dirs(test_path.resolve(), allowed_dirs)
        assert result is True

    def test_multiple_allowed_dirs_second_match(self, tmp_path):
        """Test matching against second allowed directory."""
        dir1 = tmp_path / "dir1"
        dir2 = tmp_path / "dir2"
        dir1.mkdir()
        dir2.mkdir()

        test_path = dir2 / "file.yaml"
        allowed_dirs = [dir1.resolve(), dir2.resolve()]

        result = _is_path_in_allowed_dirs(test_path.resolve(), allowed_dirs)
        assert result is True

    def test_sibling_directory_not_allowed(self, tmp_path):
        """Test that sibling directories are not considered within each other."""
        dir1 = tmp_path / "dir1"
        dir2 = tmp_path / "dir2"
        dir1.mkdir()
        dir2.mkdir()

        test_path = dir2 / "file.yaml"
        allowed_dirs = [dir1.resolve()]

        result = _is_path_in_allowed_dirs(test_path.resolve(), allowed_dirs)
        assert result is False

    def test_parent_directory_not_in_child(self, tmp_path):
        """Test that parent directory is not considered within child directory."""
        child_dir = tmp_path / "child"
        child_dir.mkdir()

        parent_path = tmp_path / "file.yaml"
        allowed_dirs = [child_dir.resolve()]

        result = _is_path_in_allowed_dirs(parent_path.resolve(), allowed_dirs)
        assert result is False
