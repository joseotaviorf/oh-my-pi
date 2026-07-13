"""Runtime-side guard for the metadata domain allowlist.

Single source of truth is ``bietlejuice/governance/domains.yml`` (bietlejuice-core),
read via :mod:`bietlejuice.governance.domain_registry`. This test proves, on the
runtime side, that:

1. F2-01's ``constants.py`` re-exports the loader (no hardcoded pattern drift), and
2. the generated Yamale schemas match the same loader pattern.

The Yamale drift is also gated in CI by ``make validate-domain-allowlist-sync``;
this keeps a fast runtime-import check close to the F2-01 consumer.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from bietlejuice.governance.domain_registry import domain_allowlist_pattern
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


def test_constants_reexport_loader_pattern() -> None:
    assert METADATA_DOMAIN_CI_ALLOWLIST_PATTERN == domain_allowlist_pattern()


@pytest.mark.parametrize("schema_file", _SCHEMA_FILES)
def test_yamale_domain_regex_matches_loader(schema_file: str) -> None:
    schema_path = _SCHEMA_DIR / schema_file
    yamale_pattern = _domain_pattern_from_schema(schema_path)
    assert yamale_pattern == domain_allowlist_pattern(), schema_file
