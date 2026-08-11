"""Layer 2 — contract checks against the real bi-etl-ejuice repo content.

Follows the precedent of test_datahub_sources.py: real filesystem, real
document_parser, real datasets/, no fakes. These tests pin the script's
behavior against actual docs/llm_context content and actual dataset files,
so a change to either that silently breaks the fan-out or budget logic is
caught here rather than only in production CI.
"""

from __future__ import annotations

import ast
import importlib.util
import sys
from pathlib import Path

import pytest
import yaml
from tars_evals.dataset import default_datasets_dir, list_dataset_stems

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "changed_dataset_stems.py"
_MODULE_NAME = "test_changed_dataset_stems_contract_script"

# sys.modules already resolvable at import time via the installed editable
# package (tests run under `uv run pytest`); this is a separate, first-party
# module that the script legitimately depends on (see its own docstring).
_ALLOWED_FIRST_PARTY_IMPORTS = frozenset({"tars_evals"})


def _load_module():
    spec = importlib.util.spec_from_file_location(_MODULE_NAME, SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[_MODULE_NAME] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def cds():
    return _load_module()


@pytest.fixture(scope="module")
def real_repo_root(cds):
    return cds.repo_root()


@pytest.fixture(scope="module")
def real_reverse_index(cds, real_repo_root):
    doc_parser = cds.load_document_parser()
    docs = cds.load_metric_docs(real_repo_root / "docs" / "llm_context" / "metric_entities")
    return cds.build_reverse_index(docs, parse_markdown=doc_parser.parse_entity_markdown)


# --------------------------------------------------------------------------
# Known fan-out pairs
# --------------------------------------------------------------------------


def test_reverse_index_resolves_nps(real_reverse_index):
    assert real_reverse_index["nps"] == {"nps_fr", "offboard_human_vs_digital_metrics"}


def test_reverse_index_resolves_house_and_listing(real_reverse_index):
    assert real_reverse_index["house-and-listing"] == {
        "credit_metrics",
        "listing_demand_funnel_conversions",
        "listing_to_rental",
        "ongoing_listings",
        "supply_retention_sale",
    }


# --------------------------------------------------------------------------
# eval stems are always a subset of list_dataset_stems()
# --------------------------------------------------------------------------


def test_resolved_eval_stems_are_subset_of_list_dataset_stems(cds, real_repo_root):
    doc_parser = cds.load_document_parser()
    diff_range = cds.resolve_diff_range(env={}, explicit_base="HEAD~20", explicit_head="HEAD")
    result = cds.resolve_scope(
        repo_root=real_repo_root,
        diff_range=diff_range,
        datasets_dir=default_datasets_dir(),
        parse_markdown=doc_parser.parse_entity_markdown,
        max_samples=10_000,
    )
    assert set(result.eval_stems) <= set(list_dataset_stems())


# --------------------------------------------------------------------------
# count_items() agrees with the real PyYAML-based loader
# --------------------------------------------------------------------------


def test_count_items_matches_load_golden_dataset_on_every_real_dataset(cds):
    from tars_evals.dataset import load_golden_dataset

    for stem in list_dataset_stems():
        path = default_datasets_dir() / f"{stem}.yaml"
        expected = len(load_golden_dataset([path]))
        actual = cds.count_items(path)
        assert actual == expected, f"{stem}: count_items={actual} vs load_golden_dataset={expected}"


def test_count_items_matches_pyyaml_safe_load_on_every_real_dataset(cds):
    for stem in list_dataset_stems():
        path = default_datasets_dir() / f"{stem}.yaml"
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
        expected = len(raw["items"])
        actual = cds.count_items(path)
        assert actual == expected, f"{stem}: count_items={actual} vs yaml.safe_load={expected}"


# --------------------------------------------------------------------------
# AST guard: the stdlib-only promise cannot silently rot
# --------------------------------------------------------------------------


def _top_level_import_roots(path: Path) -> set[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    roots: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                roots.add(alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            roots.add(node.module.split(".")[0])
    return roots


def test_script_imports_are_stdlib_or_allowed_first_party():
    roots = _top_level_import_roots(SCRIPT)
    stdlib = set(sys.stdlib_module_names)
    offenders = roots - stdlib - _ALLOWED_FIRST_PARTY_IMPORTS
    assert not offenders, f"non-stdlib, non-allowlisted top-level imports: {offenders}"


def test_repo_bootstrap_shim_is_itself_stdlib_only():
    """The one first-party import (tars_evals.repo_bootstrap) must stay
    stdlib-only transitively, or the script's "runs before uv sync" promise
    silently breaks.
    """
    repo_bootstrap_path = (
        Path(__file__).resolve().parents[1] / "src" / "tars_evals" / "repo_bootstrap.py"
    )
    roots = _top_level_import_roots(repo_bootstrap_path)
    stdlib = set(sys.stdlib_module_names)
    offenders = roots - stdlib
    assert not offenders, f"repo_bootstrap.py has non-stdlib imports: {offenders}"


def test_document_parser_and_its_siblings_are_stdlib_only(real_repo_root):
    """document_parser.py (live-loaded at runtime, not statically imported)
    and its own sync.* imports must also stay stdlib-only.
    """
    sync_dir = real_repo_root / "dags" / "governance" / "datahub_business_context" / "sync"
    stdlib = set(sys.stdlib_module_names)
    for name in ("document_parser.py", "constants.py", "markdown_sanitizer.py"):
        module_path = sync_dir / name
        roots = _top_level_import_roots(module_path)
        # These modules import each other by first-party name (e.g.
        # "from sync.constants import ...") -- allow "sync" itself.
        offenders = roots - stdlib - {"sync"}
        assert not offenders, f"{name} has non-stdlib imports: {offenders}"
