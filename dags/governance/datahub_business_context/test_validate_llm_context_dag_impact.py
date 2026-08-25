"""Tests for DAG → llm_context golden-query impact validation."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml
from golden_query_schema_validator import column_refs_for_table_in_sql
from llm_context_dag_impact_validator import (
    build_golden_query_index,
    collect_table_impacts,
    diff_metadata_columns,
    filter_dag_impact_paths,
    validate_table_impacts,
)


def _write_metadata(
    repo_root: Path,
    *,
    dag: str = "dw_visit",
    layer: str = "dw",
    table: str = "fact_visits",
    database_name: str = "dw_visit",
    columns: list[str],
) -> str:
    meta_dir = repo_root / "dags" / "rent" / dag / "metadata" / layer
    meta_dir.mkdir(parents=True, exist_ok=True)
    rel = f"dags/rent/{dag}/metadata/{layer}/{table}.yml"
    path = repo_root / rel
    payload = {
        "database_name": database_name,
        "table_name": table,
        "description": "Test table for llm_context DAG impact validation in CI gate.",
        "domain": "For Rent",
        "owner": "owner@quintoandar.com.br",
        "columns": {
            col: {"description": f"Column {col} used by golden-query impact tests."}
            for col in columns
        },
    }
    path.write_text(yaml.safe_dump(payload), encoding="utf-8")
    return rel


def _write_entity_doc(repo_root: Path, *, name: str, sql: str) -> Path:
    doc_dir = repo_root / "docs" / "llm_context" / "domain_entities"
    doc_dir.mkdir(parents=True, exist_ok=True)
    content = f"""# Visits

## Ownership
owner@quintoandar.com.br

## Overview
Visit entity for impact tests.

## Glossary and Synonyms
- visit: property visit

## Tables
- `dw_visit.fact_visits` — visit fact table

## Dos and Don'ts
- Filter on partition columns.

## Golden Queries

### Query 1 — visits count
```sql
{sql}
```
"""
    path = doc_dir / f"{name}.md"
    path.write_text(content, encoding="utf-8")
    return path


def test_filter_dag_impact_paths_keeps_metadata_only():
    paths = filter_dag_impact_paths(
        [
            "dags/rent/dw_visit/queries/dw/fact_visits.sql",
            "dags/rent/dw_visit/metadata/dw/fact_visits.yml",
            "docs/llm_context/domain_entities/visits.md",
        ]
    )
    assert paths == ["dags/rent/dw_visit/metadata/dw/fact_visits.yml"]


def test_column_refs_for_table_in_sql_resolves_alias(tmp_path: Path):
    sql = "SELECT v.sk_visit FROM dw_visit.fact_visits AS v WHERE v.id_house = 1"
    result = column_refs_for_table_in_sql(
        sql,
        schema="dw_visit",
        table="fact_visits",
        known_columns={"sk_visit", "id_house"},
    )
    assert result.verified is True
    assert result.target_in_query is True
    assert result.refs == frozenset({"sk_visit", "id_house"})


def test_column_refs_for_table_in_sql_parse_failure_is_unverified(monkeypatch):
    import golden_query_schema_validator as gqs

    def _boom(*_args, **_kwargs):
        raise ValueError("parse failed in test")

    monkeypatch.setattr(gqs.sqlglot, "parse_one", _boom)
    sql = "SELECT sk_visit FROM dw_visit.fact_visits WHERE {{{bad"
    result = column_refs_for_table_in_sql(
        sql,
        schema="dw_visit",
        table="fact_visits",
        known_columns={"sk_visit"},
    )
    assert result.verified is False
    assert result.target_in_query is True
    assert "sk_visit" in result.refs


def test_validate_table_impacts_unparseable_sql_blocks_when_column_still_present(
    tmp_path: Path, monkeypatch
):
    import golden_query_schema_validator as gqs

    def _boom(*_args, **_kwargs):
        raise ValueError("parse failed in test")

    monkeypatch.setattr(gqs.sqlglot, "parse_one", _boom)
    monkeypatch.setattr(
        "llm_context_dag_impact_validator._REPO_ROOT",
        tmp_path,
    )
    _write_entity_doc(
        tmp_path,
        name="visits",
        sql="SELECT sk_visit FROM dw_visit.fact_visits WHERE {{{bad",
    )
    doc = tmp_path / "docs/llm_context/domain_entities/visits.md"
    index = build_golden_query_index([doc])
    impact = type(
        "Impact",
        (),
        {
            "schema": "dw_visit",
            "table": "fact_visits",
            "metadata_path": "dags/rent/dw_visit/metadata/dw/fact_visits.yml",
            "removed_columns": frozenset({"sk_visit"}),
            "added_columns": frozenset(),
            "metadata_deleted": False,
        },
    )()
    errors, warnings = validate_table_impacts([impact], index)
    assert errors
    assert any("sk_visit" in e for e in errors)
    assert not warnings


def test_validate_table_impacts_unparseable_sql_blocks_even_without_text_match(
    tmp_path: Path, monkeypatch
):
    import golden_query_schema_validator as gqs

    def _boom(*_args, **_kwargs):
        raise ValueError("parse failed in test")

    monkeypatch.setattr(gqs.sqlglot, "parse_one", _boom)
    monkeypatch.setattr(
        "llm_context_dag_impact_validator._REPO_ROOT",
        tmp_path,
    )
    _write_entity_doc(
        tmp_path,
        name="visits",
        sql="SELECT 1 FROM dw_visit.fact_visits WHERE {{{bad",
    )
    doc = tmp_path / "docs/llm_context/domain_entities/visits.md"
    index = build_golden_query_index([doc])
    impact = type(
        "Impact",
        (),
        {
            "schema": "dw_visit",
            "table": "fact_visits",
            "metadata_path": "dags/rent/dw_visit/metadata/dw/fact_visits.yml",
            "removed_columns": frozenset({"sk_visit"}),
            "added_columns": frozenset(),
            "metadata_deleted": False,
        },
    )()
    errors, warnings = validate_table_impacts([impact], index)
    assert errors
    assert any("could not parse" in e for e in errors)
    assert not warnings


def test_validate_table_impacts_removed_column_is_blocking(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(
        "llm_context_dag_impact_validator._REPO_ROOT",
        tmp_path,
    )
    _write_entity_doc(
        tmp_path,
        name="visits",
        sql="SELECT sk_visit FROM dw_visit.fact_visits",
    )
    doc = tmp_path / "docs/llm_context/domain_entities/visits.md"
    index = build_golden_query_index([doc])
    impact = type(
        "Impact",
        (),
        {
            "schema": "dw_visit",
            "table": "fact_visits",
            "metadata_path": "dags/rent/dw_visit/metadata/dw/fact_visits.yml",
            "removed_columns": frozenset({"sk_visit"}),
            "added_columns": frozenset(),
            "metadata_deleted": False,
        },
    )()
    errors, warnings = validate_table_impacts([impact], index)
    assert errors
    assert any("sk_visit" in e for e in errors)
    assert not warnings


def test_validate_table_impacts_added_column_emits_warning(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(
        "llm_context_dag_impact_validator._REPO_ROOT",
        tmp_path,
    )
    _write_entity_doc(
        tmp_path,
        name="visits",
        sql="SELECT sk_visit FROM dw_visit.fact_visits",
    )
    doc = tmp_path / "docs/llm_context/domain_entities/visits.md"
    index = build_golden_query_index([doc])
    impact = type(
        "Impact",
        (),
        {
            "schema": "dw_visit",
            "table": "fact_visits",
            "metadata_path": "dags/rent/dw_visit/metadata/dw/fact_visits.yml",
            "removed_columns": frozenset(),
            "added_columns": frozenset({"dt_new_metric"}),
            "metadata_deleted": False,
        },
    )()
    errors, warnings = validate_table_impacts([impact], index)
    assert not errors
    assert warnings
    assert any("dt_new_metric" in w for w in warnings)


def test_validate_table_impacts_remove_does_not_warn_on_add(
    tmp_path: Path, monkeypatch
):
    monkeypatch.setattr(
        "llm_context_dag_impact_validator._REPO_ROOT",
        tmp_path,
    )
    _write_entity_doc(
        tmp_path,
        name="visits",
        sql="SELECT sk_visit FROM dw_visit.fact_visits",
    )
    doc = tmp_path / "docs/llm_context/domain_entities/visits.md"
    index = build_golden_query_index([doc])
    impact = type(
        "Impact",
        (),
        {
            "schema": "dw_visit",
            "table": "fact_visits",
            "metadata_path": "dags/rent/dw_visit/metadata/dw/fact_visits.yml",
            "removed_columns": frozenset({"sk_visit"}),
            "added_columns": frozenset({"sk_visit_new"}),
            "metadata_deleted": False,
        },
    )()
    errors, warnings = validate_table_impacts([impact], index)
    assert errors
    assert not warnings


def test_diff_metadata_columns_detects_add_and_remove(tmp_path: Path, monkeypatch):
    rel = _write_metadata(
        tmp_path,
        columns=["sk_visit", "id_house"],
    )
    old_path = tmp_path / rel
    old_content = old_path.read_text(encoding="utf-8")
    payload = yaml.safe_load(old_content)
    payload["columns"] = {
        "sk_visit": payload["columns"]["sk_visit"],
        "dt_new": {"description": "New column for impact validation tests."},
    }
    old_path.write_text(yaml.safe_dump(payload), encoding="utf-8")

    def _fake_git_show(rel_path: str, from_ref: str, *, repo_root=None):
        if rel_path == rel:
            return old_content
        return None

    monkeypatch.setattr(
        "llm_context_dag_impact_validator.git_file_at_ref",
        _fake_git_show,
    )

    removed, added, deleted = diff_metadata_columns(
        rel,
        "HEAD",
        repo_root=tmp_path,
    )
    assert deleted is False
    assert "id_house" in removed
    assert "dt_new" in added


def test_collect_table_impacts_from_changed_metadata(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(
        "llm_context_dag_impact_validator._REPO_ROOT",
        tmp_path,
    )
    rel = _write_metadata(tmp_path, columns=["sk_visit"])
    path = tmp_path / rel
    payload = yaml.safe_load(path.read_text(encoding="utf-8"))
    payload["columns"]["id_house"] = {
        "description": "House id column for collect_table_impacts test."
    }
    path.write_text(yaml.safe_dump(payload), encoding="utf-8")

    impacts = collect_table_impacts([rel], "HEAD", repo_root=tmp_path)
    assert len(impacts) == 1
    assert impacts[0].schema == "dw_visit"
    assert impacts[0].table == "fact_visits"
    assert "id_house" in impacts[0].added_columns


def test_cli_main_changed_only_no_files(monkeypatch: pytest.MonkeyPatch):
    import validate_llm_context_dag_impact as cli

    monkeypatch.setattr(cli, "_git_changed_dag_paths", lambda _branch: [])
    assert cli.main(["--changed-only", "-b", "feature/x"]) == 0
