"""
Secure path validation utilities to prevent path traversal attacks (CWE-23).

This module provides functions to safely validate file paths from user input,
ensuring they resolve to allowed locations and preventing directory traversal
attacks.
"""

import os
from pathlib import Path
from typing import List, Optional

from bietlejuice.qube.jobs.common.logging_config import get_logger

logger = get_logger("path_validator")


class PathSecurityError(Exception):
    """Raised when a path fails security validation."""

    pass


def validate_spec_path(
    path_str: str,
    allowed_base_dirs: Optional[List[Path]] = None,
    must_exist: bool = True,
) -> Path:
    """
    Validate and sanitize a spec file path to prevent path traversal attacks.

    This function provides defense-in-depth validation:
    1. Resolves the path to its canonical absolute form
    2. Verifies the file exists (if must_exist=True)
    3. Ensures the resolved path is within allowed base directories
    4. Prevents symlink-based attacks through canonical resolution

    Args:
        path_str: User-provided path string (relative or absolute)
        allowed_base_dirs: List of allowed base directories. If None, uses:
            - Current working directory
            - Common spec directories (qube/specs, specs)
        must_exist: If True, requires the file to exist (default: True)

    Returns:
        Validated Path object with canonical absolute path

    Raises:
        PathSecurityError: If path fails security validation
        FileNotFoundError: If file doesn't exist and must_exist=True

    Security Notes:
        - Prevents directory traversal (e.g., ../../../etc/passwd)
        - Prevents symlink attacks through canonical path resolution
        - Validates against explicit allowlist of base directories
        - All validation errors are logged for security auditing

    Examples:
        >>> validate_spec_path("specs/dimensions/user.yaml")
        PosixPath('/project/specs/dimensions/user.yaml')

        >>> validate_spec_path("../../../etc/passwd")
        PathSecurityError: Path is outside allowed directories
    """
    if not path_str or not isinstance(path_str, str):
        logger.error(f"Invalid path string: {path_str}")
        raise PathSecurityError(f"Path must be a non-empty string: {path_str}")

    # Security: Resolve to canonical absolute path (prevents .. and symlink attacks)
    try:
        if must_exist:
            # strict=True ensures file exists and resolves symlinks
            resolved_path = Path(path_str).resolve(strict=True)
        else:
            # For paths that may not exist yet, resolve without strict mode
            resolved_path = Path(path_str).resolve(strict=False)
            # Check parent directory exists
            if not resolved_path.parent.exists():
                raise FileNotFoundError(
                    f"Parent directory does not exist: {resolved_path.parent}"
                )
    except (OSError, RuntimeError) as e:
        logger.error(f"Failed to resolve path: {path_str} - {e}")
        raise FileNotFoundError(f"Spec file not found or invalid: {path_str}") from e

    # Determine allowed base directories
    if allowed_base_dirs is None:
        allowed_base_dirs = _get_default_allowed_dirs()

    # Security: Ensure resolved path is within an allowed base directory
    if not _is_path_in_allowed_dirs(resolved_path, allowed_base_dirs):
        logger.error(f"Path traversal attempt detected: {path_str} -> {resolved_path}")
        logger.error(f"Allowed base directories: {[str(d) for d in allowed_base_dirs]}")
        raise PathSecurityError(
            f"Path is outside allowed directories: {path_str}\n"
            f"Resolved to: {resolved_path}\n"
            f"Allowed base directories: {[str(d) for d in allowed_base_dirs]}"
        )

    logger.debug(f"Path validated successfully: {path_str} -> {resolved_path}")
    return resolved_path


def _get_default_allowed_dirs() -> List[Path]:
    """
    Get default allowed base directories for spec files.

    Returns:
        List of allowed base directory paths (resolved to canonical form)
    """
    allowed_dirs = []

    # Current working directory (typical for local development)
    cwd = Path.cwd().resolve()
    allowed_dirs.append(cwd)

    # If QUBE_SPECS_ROOT environment variable is set, allow it
    specs_root_env = os.getenv("QUBE_SPECS_ROOT")
    if specs_root_env:
        try:
            specs_root = Path(specs_root_env).resolve()
            if specs_root.exists():
                allowed_dirs.append(specs_root)
        except (OSError, RuntimeError):
            logger.warning(f"Invalid QUBE_SPECS_ROOT: {specs_root_env}")

    # Common spec directories relative to CWD
    for spec_subdir in ["qube/specs", "specs", "qube", "."]:
        spec_dir = (cwd / spec_subdir).resolve()
        if spec_dir.exists() and spec_dir not in allowed_dirs:
            allowed_dirs.append(spec_dir)

    logger.debug(f"Default allowed directories: {[str(d) for d in allowed_dirs]}")
    return allowed_dirs


def _is_path_in_allowed_dirs(resolved_path: Path, allowed_dirs: List[Path]) -> bool:
    """
    Check if a resolved path is within any of the allowed base directories.

    Args:
        resolved_path: Canonical absolute path to check
        allowed_dirs: List of allowed base directories (canonical absolute paths)

    Returns:
        True if path is within an allowed directory, False otherwise

    Security Notes:
        - Uses Path.is_relative_to() for safe path comparison
        - Both paths must be resolved to canonical form before calling
        - Prevents path traversal through string manipulation
    """
    for allowed_dir in allowed_dirs:
        try:
            # is_relative_to() returns True if path is under allowed_dir
            # This is safe against path traversal attacks when both paths are resolved
            if resolved_path.is_relative_to(allowed_dir):
                return True
        except (ValueError, AttributeError):
            # is_relative_to() not available in Python < 3.9
            # Fall back to string-based comparison (less safe but functional)
            try:
                resolved_path.relative_to(allowed_dir)
                return True
            except ValueError:
                continue

    return False
