"""PR 1 guardrail: prove the loader reproduces the *current* allowlist exactly.

The GOLDEN constant pins the byte-identical pattern. The cross-checks pin GOLDEN
to the live repo state (the 5 Yamale schemas and the runtime ``constants.py``) so
that, until those consumers are switched to the loader, any drift fails loudly.
Cross-checks skip gracefully when run outside the repo tree (e.g. from a wheel).
"""

from __future__ import annotations

import ast
import re
from pathlib import Path

import pytest

from bietlejuice.governance import domain_registry

# Historical pattern, copied verbatim from constants.py / the Yamale schemas.
GOLDEN_PATTERN = (
    "Agents|Cross|Data Ops & Governance|Data Life Cycle|Fintech|For Rent|For Sale|"
    "Growth|International|Journey Optimizer|MLOps|People|QCX|Rede|"
    "Support and Services|Tech Platform|Data Platform|Conversational XP|"
    "DS Pricing|Atlas DB|Broker XP|House and Listing"
)

_REPO_ROOT = Path(__file__).resolve().parents[5]
_SCHEMA_DIR = (
    _REPO_ROOT / "packages/bietlejuice-compiler/scripts/services/metadata_file_schemas"
)
_SCHEMA_FILES = ("raw", "clean", "core", "enrich_dw", "metric")
_CONSTANTS_FILE = (
    _REPO_ROOT
    / "packages/bietlejuice-runtime/src/bietlejuice/governance"
    / "fairness_assessment/constants.py"
)
_REGEX_ARG = re.compile(r"domain:\s*regex\('([^']*)'\)")


def test_pattern_is_byte_identical_to_golden():
    assert domain_registry.domain_allowlist_pattern() == GOLDEN_PATTERN


def test_order_is_preserved():
    # 22 domains, order matters for the regex alternation.
    assert domain_registry.active_domains() == tuple(GOLDEN_PATTERN.split("|"))


# Regex operators that would change matching semantics inside a plain ``|``-joined
# alternation used with ``fullmatch`` (default flags). Space, ``&`` and ``#`` are
# literal here — ``re.escape`` rewrites them but they do not need escaping.
_DANGEROUS_REGEX_CHARS = set(r".^$*+?{}[]()|\\")


def test_no_value_contains_a_breaking_regex_metachar():
    for domain in domain_registry.active_domains():
        offending = _DANGEROUS_REGEX_CHARS & set(domain)
        assert not offending, (
            f"{domain!r} contains regex operator(s) {sorted(offending)}; the plain "
            "'|'.join in domain_allowlist_pattern() would no longer be safe."
        )


def test_regex_fullmatches_each_active_domain():
    rx = domain_registry.domain_allowlist_regex()
    for domain in domain_registry.active_domains():
        assert rx.fullmatch(domain), domain


@pytest.mark.parametrize("layer", _SCHEMA_FILES)
def test_matches_live_yamale_schema(layer):
    schema = _SCHEMA_DIR / f"{layer}_schema.yml"
    if not schema.exists():
        pytest.skip(f"schema not found outside repo tree: {schema}")
    match = _REGEX_ARG.search(schema.read_text(encoding="utf-8"))
    assert match, f"no `domain: regex(...)` line in {schema}"
    assert match.group(1) == domain_registry.domain_allowlist_pattern()


def test_runtime_constants_reexports_loader():
    """Guard against re-hardcoding: constants.py must derive the pattern from the
    loader (a call), not a string literal. Runtime-side equality is asserted in the
    bietlejuice-runtime suite (which can import the constants module directly)."""
    if not _CONSTANTS_FILE.exists():
        pytest.skip(f"constants.py not found outside repo tree: {_CONSTANTS_FILE}")
    tree = ast.parse(_CONSTANTS_FILE.read_text(encoding="utf-8"))
    value_node = None
    for node in ast.walk(tree):
        target = None
        if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            target = node.target.id
        elif isinstance(node, ast.Assign) and node.targets:
            first = node.targets[0]
            target = first.id if isinstance(first, ast.Name) else None
        if target == "METADATA_DOMAIN_CI_ALLOWLIST_PATTERN" and node.value is not None:
            value_node = node.value
            break
    assert value_node is not None, "pattern constant not found in constants.py"
    assert isinstance(value_node, ast.Call), (
        "METADATA_DOMAIN_CI_ALLOWLIST_PATTERN should re-export the loader "
        "(a call), not hardcode a string literal."
    )
    assert getattr(value_node.func, "id", None) == "domain_allowlist_pattern"


def test_folder_to_domain_resolves_known_folders():
    assert domain_registry.folder_to_domain("for_rent") == "For Rent"
    assert domain_registry.folder_to_domain("governance") == "Data Ops & Governance"
    assert (
        domain_registry.folder_to_domain("support_and_service")
        == "Support and Services"
    )


def test_folder_to_domain_none_for_unmapped_or_ambiguous():
    # Mixed / per-DAG / non-domain folders and unknown folders must return None so
    # generate_metadata leaves `domain:` for a human instead of guessing.
    for folder in ("platform", "core", "ops_poc", "planning_and_performance", "nope"):
        assert domain_registry.folder_to_domain(folder) is None, folder


def test_folder_mappings_only_target_allowlisted_domains():
    allowed = set(domain_registry.active_domains())
    for folder, domain in domain_registry._load()["repo_folder_mappings"].items():
        assert domain in allowed, f"{folder} -> {domain!r} is not in the allowlist"
