"""Tests for shared repo root discovery and document_parser bootstrap."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest
from tars_evals import repo_bootstrap
from tars_evals.repo_bootstrap import (
    _discover_repo_root,
    load_document_parser,
    repo_root,
)


def test_discover_repo_root_walks_ancestors(tmp_path: Path):
    nest = tmp_path / "packages" / "tars-evals" / "src" / "tars_evals"
    nest.mkdir(parents=True)
    llm = tmp_path / "docs" / "llm_context"
    llm.mkdir(parents=True)
    assert _discover_repo_root(nest / "repo_bootstrap.py") == tmp_path


def test_discover_repo_root_missing_llm_context_raises(tmp_path: Path):
    start = tmp_path / "orphan" / "module.py"
    start.parent.mkdir(parents=True)
    start.write_text("# placeholder\n", encoding="utf-8")
    with pytest.raises(RuntimeError, match="docs/llm_context"):
        _discover_repo_root(start)


def test_repo_root_finds_llm_context():
    root = repo_root()
    assert (root / "docs" / "llm_context").is_dir()
    assert repo_root() is root  # cached identity


def test_load_document_parser_cached_identity_and_api():
    first = load_document_parser()
    second = load_document_parser()
    assert first is second
    assert first.__name__ == "tars_evals_document_parser"
    assert callable(getattr(first, "parse_entity_markdown", None))


def test_load_document_parser_missing_file_clear_error(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    load_document_parser.cache_clear()
    sys.modules.pop("tars_evals_document_parser", None)

    monkeypatch.setattr(repo_bootstrap, "repo_root", lambda: tmp_path)

    with pytest.raises(RuntimeError, match="document_parser not found"):
        load_document_parser()

    load_document_parser.cache_clear()
    sys.modules.pop("tars_evals_document_parser", None)


def test_load_document_parser_exec_failure_clears_sys_modules(
    tmp_path, monkeypatch
):
    root = tmp_path / "repo"
    parser = (
        root
        / "dags/governance/datahub_business_context/sync/document_parser.py"
    )
    parser.parent.mkdir(parents=True)
    (root / "docs/llm_context").mkdir(parents=True)
    parser.write_text("raise RuntimeError('broken parser')\n", encoding="utf-8")

    monkeypatch.setattr(repo_bootstrap, "repo_root", lambda: root)
    repo_bootstrap.load_document_parser.cache_clear()
    sys.modules.pop(repo_bootstrap._PARSER_MOD_NAME, None)

    try:
        with pytest.raises(RuntimeError, match="broken parser"):
            repo_bootstrap.load_document_parser()

        assert repo_bootstrap._PARSER_MOD_NAME not in sys.modules

        parser.write_text("MARKER = 'loaded'\n", encoding="utf-8")
        repo_bootstrap.load_document_parser.cache_clear()
        module = repo_bootstrap.load_document_parser()
        assert module.MARKER == "loaded"
    finally:
        repo_bootstrap.load_document_parser.cache_clear()
        sys.modules.pop(repo_bootstrap._PARSER_MOD_NAME, None)
