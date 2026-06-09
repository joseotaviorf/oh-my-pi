"""Interim drift guard: Yamale domain regex must match runtime F2-01 allowlist.

Replaced by SSOT CI once metadata_domain_allowlist.yml lands (follow-up PR).
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from bietlejuice.governance.fairness_assessment.constants import (
    METADATA_DOMAIN_CI_ALLOWLIST_PATTERN,
)

_REPO_ROOT = Path(__file__).resolve().parents[7]
_SCHEMA_DIR = (
    _REPO_ROOT / "packages/bietlejuice-compiler/scripts/services/metadata_file_schemas"
)
_DOMAIN_REGEX_RE = re.compile(r"^domain:\s*regex\('(.+)'\)\s*$")
_SCHEMA_FILES = (
    "raw_schema.yml",
    "clean_schema.yml",
    "core_schema.yml",
    "enrich_dw_schema.yml",
    "metric_schema.yml",
)


def _domain_pattern_from_schema(path: Path) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        match = _DOMAIN_REGEX_RE.match(line.strip())
        if match:
            return match.group(1)
    raise AssertionError(f"No domain regex line in {path}")


@pytest.mark.parametrize("schema_file", _SCHEMA_FILES)
def test_yamale_domain_regex_matches_runtime_allowlist(schema_file: str) -> None:
    # Arrange
    schema_path = _SCHEMA_DIR / schema_file
    # Act
    yamale_pattern = _domain_pattern_from_schema(schema_path)
    # Assert
    assert yamale_pattern == METADATA_DOMAIN_CI_ALLOWLIST_PATTERN, schema_file
