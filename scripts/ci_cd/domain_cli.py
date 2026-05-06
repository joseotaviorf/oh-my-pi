"""Shared ``argparse`` ``type=`` callbacks for CI validation scripts.

Sanitises CLI values before they are joined into paths or passed to ``open()``, which
keeps Snyk Code path-traversal findings on local tooling in check.
"""

from __future__ import annotations

import argparse
import re

_VALID_DOMAIN_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_\-]*$")
_VALID_BRANCH_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9/_.\-@]*$")
_VALID_FILE_PATH_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9/_\-\.]*$")
_VALID_PROFILE_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_\-]*$")


def domain_arg_type(value: str) -> str:
    """``dags/<domain>/`` folder name (e.g. ``for_rent``)."""
    if not _VALID_DOMAIN_RE.match(value):
        raise argparse.ArgumentTypeError(
            f"Invalid domain name {value!r}: only alphanumeric characters, "
            "underscores, and hyphens are allowed."
        )
    return value


def branch_name_arg_type(value: str) -> str:
    """Git branch / ref label (matches prior ``validate_lineage_consistency`` rules)."""
    if value == "":
        return value
    if not _VALID_BRANCH_RE.match(value):
        raise argparse.ArgumentTypeError(
            f"Invalid branch name {value!r}: only alphanumeric characters, "
            "/, _, ., -, and @ are allowed."
        )
    return value


def repo_relative_file_arg_type(value: str) -> str:
    """Repo-relative path for ``-f`` / ``--file`` (no ``..`` segments)."""
    clean = value.replace("\\", "/")
    parts = [p for p in clean.split("/") if p]
    if ".." in parts:
        raise argparse.ArgumentTypeError(
            f"Invalid file path {value!r}: path traversal sequences are not allowed."
        )
    if not _VALID_FILE_PATH_RE.match(clean):
        raise argparse.ArgumentTypeError(
            f"Invalid file path {value!r}: only alphanumeric characters, "
            "/, _, -, and . are allowed."
        )
    return clean


def source_layer_profile_arg_type(value: str) -> str:
    """``--profile`` value matching ``cli_profile`` keys in ``profiles/*.yml``."""
    if not _VALID_PROFILE_RE.match(value):
        raise argparse.ArgumentTypeError(
            f"Invalid profile name {value!r}: only alphanumeric characters, "
            "underscores, and hyphens are allowed."
        )
    return value
