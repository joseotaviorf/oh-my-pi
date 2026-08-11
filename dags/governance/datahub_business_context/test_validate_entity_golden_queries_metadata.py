"""Tests for repo-metadata golden-query schema validation."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml
from golden_query_metadata_validator import (
    MetadataSchemaClient,
    build_metadata_column_index,
)
from golden_query_schema_validator import (
    normalize_table_ref,
    substitute_sql_placeholders,
    table_refs_in_sql,
    validate_golden_queries,
    validate_golden_query_sql,
    validate_trino_sql_syntax,
)


class _FakeGoldenQuery:
    def __init__(self, name: str, sql: str) -> None:
        self.name = name
        self.sql = sql


def _write_metadata(
    tmp_path: Path,
    *,
    database_name: str,
    table_name: str,
    columns: list[str],
) -> Path:
    dag_dir = tmp_path / "dags" / "rent" / "dw_rent"
    meta_dir = dag_dir / "metadata" / "dw"
    meta_dir.mkdir(parents=True)
    path = meta_dir / f"{table_name}.yml"
    payload = {
        "database_name": database_name,
        "table_name": table_name,
        "description": "Test table for golden-query metadata validation.",
        "domain": "For Rent",
        "owner": "owner@quintoandar.com.br",
        "columns": {
            col: {"description": f"Column {col} for validation tests."}
            for col in columns
        },
    }
    path.write_text(yaml.safe_dump(payload), encoding="utf-8")
    return path


def test_substitute_sql_placeholders_replaces_common_tokens():
    sql = (
        "SELECT sk FROM dw.foo.fact_bar "
        "WHERE dt >= DATE '{start_date}' AND year = {start_year}"
    )
    out = substitute_sql_placeholders(sql)
    assert "{start_date}" not in out
    assert "{start_year}" not in out
    assert "2024" in out


def test_substitute_sql_placeholders_neutralizes_unknown_tokens_outside_quotes():
    sql = "SELECT {cohort_col} FROM dw.foo.fact_bar"
    out = substitute_sql_placeholders(sql)
    assert "{cohort_col}" not in out
    assert "'2024-01-01'" in out


def test_substitute_sql_placeholders_preserves_braces_inside_string_literals():
    sql = (
        "SELECT * FROM (VALUES "
        "('ig','Meta'), ('{{site_source_name}}','Meta'), ('{site_source_name}','Meta')"
        ") AS t(utm_source, origin)"
    )
    out = substitute_sql_placeholders(sql)
    assert "'{{site_source_name}}'" in out
    assert "'{site_source_name}'" in out
    assert "2024-01-01" not in out


def test_substitute_sql_placeholders_preserves_braces_in_json_path_literal():
    sql = "SELECT json_extract_scalar(variants, '$.{experiment_name}') FROM dw.foo.t"
    out = substitute_sql_placeholders(sql)
    assert "'$.{experiment_name}'" in out


def test_substitute_sql_placeholders_mixes_real_placeholder_and_data_literal():
    sql = (
        "SELECT 1 FROM dw.foo.fact_bar "
        "WHERE dt >= DATE '{start_date}' AND utm_source = '{{site_source_name}}'"
    )
    out = substitute_sql_placeholders(sql)
    assert "{start_date}" not in out
    assert "DATE '2024-01-01'" in out
    assert "'{{site_source_name}}'" in out


def test_validate_trino_sql_syntax_accepts_braced_data_literals():
    sql = (
        "SELECT json_extract_scalar(variants, '$.{experiment_name}') AS ab_test "
        "FROM (VALUES ('{{site_source_name}}','Meta')) AS t(utm_source, origin) "
        "WHERE dt >= DATE '{start_date}'"
    )
    errors, _ = validate_trino_sql_syntax(sql, query_label="Query 1")
    assert errors == []


def test_table_refs_in_sql_finds_from_and_join():
    sql = """
    WITH base AS (SELECT 1 FROM dw_a.t1)
    SELECT *
    FROM dw_b.t2 a
    JOIN dw_c.t3 b ON a.id = b.id
    """
    refs = table_refs_in_sql(sql)
    assert ("dw_a", "t1") in refs
    assert ("dw_b", "t2") in refs
    assert ("dw_c", "t3") in refs


def test_table_refs_in_sql_strips_hive_catalog_prefix():
    sql = "SELECT 1 FROM hive.datalake_langfuse_clean.scores AS sc"
    refs = table_refs_in_sql(sql)
    assert refs == [("datalake_langfuse_clean", "scores")]


def test_normalize_table_ref_strips_hive_catalog():
    assert normalize_table_ref("hive", "datalake_langfuse_clean", "scores") == (
        "datalake_langfuse_clean",
        "scores",
    )
    assert normalize_table_ref("", "dw_sale", "fact_offers") == (
        "dw_sale",
        "fact_offers",
    )


def test_build_metadata_column_index_reads_yaml(tmp_path: Path):
    _write_metadata(
        tmp_path,
        database_name="dw_visit",
        table_name="fact_visits",
        columns=["sk_visit", "id_house"],
    )
    index = build_metadata_column_index(dags_root=tmp_path / "dags")
    key = ("dw_visit", "fact_visits")
    assert key in index
    assert index[key].columns == {"sk_visit", "id_house"}


def test_validate_golden_query_sql_missing_table_is_blocking(tmp_path: Path):
    _write_metadata(
        tmp_path,
        database_name="dw_visit",
        table_name="fact_visits",
        columns=["sk_visit"],
    )
    client = MetadataSchemaClient(
        index=build_metadata_column_index(dags_root=tmp_path / "dags")
    )
    errors, warnings = validate_golden_query_sql(
        "SELECT sk_visit FROM dw_visit.fact_visits",
        query_label="Query 1",
        client=client,
    )
    assert errors == []
    assert warnings == []

    errors, warnings = validate_golden_query_sql(
        "SELECT sk_visit FROM dw_missing.fact_visits",
        query_label="Query 2",
        client=client,
    )
    assert any("not found in repo metadata" in e for e in errors)
    assert not warnings


def test_validate_golden_query_sql_missing_column_is_blocking(tmp_path: Path):
    _write_metadata(
        tmp_path,
        database_name="dw_visit",
        table_name="fact_visits",
        columns=["sk_visit"],
    )
    client = MetadataSchemaClient(
        index=build_metadata_column_index(dags_root=tmp_path / "dags")
    )
    errors, _ = validate_golden_query_sql(
        "SELECT sk_typo FROM dw_visit.fact_visits",
        query_label="Query 1",
        client=client,
    )
    assert any("sk_typo" in e and "not found" in e for e in errors)


def test_validate_golden_query_sql_resolves_table_alias(tmp_path: Path):
    _write_metadata(
        tmp_path,
        database_name="dw_visit",
        table_name="fact_visits",
        columns=["sk_visit", "id_house"],
    )
    client = MetadataSchemaClient(
        index=build_metadata_column_index(dags_root=tmp_path / "dags")
    )
    errors, warnings = validate_golden_query_sql(
        "SELECT v.sk_visit, v.id_house FROM dw_visit.fact_visits v",
        query_label="Query 1",
        client=client,
    )
    assert errors == []
    assert warnings == []


def test_validate_golden_query_sql_skips_cte_table_alias_columns(tmp_path: Path):
    _write_metadata(
        tmp_path,
        database_name="dw_sale",
        table_name="fact_offers",
        columns=["ts_offer_submitted"],
    )
    client = MetadataSchemaClient(
        index=build_metadata_column_index(dags_root=tmp_path / "dags")
    )
    sql = """
    WITH offer_metrics AS (
        SELECT COUNT(*) AS offers_submitted
        FROM dw_sale.fact_offers AS o
        GROUP BY 1
    )
    SELECT o.offers_submitted
    FROM offer_metrics AS o
    ORDER BY offers_submitted DESC
    """
    errors, warnings = validate_golden_query_sql(
        sql,
        query_label="Query 1",
        client=client,
    )
    assert errors == []


def test_validate_golden_query_sql_skips_select_alias_in_order_by(tmp_path: Path):
    _write_metadata(
        tmp_path,
        database_name="dw_sale",
        table_name="fact_offers",
        columns=["ts_offer_submitted", "sk_broker_supply", "sk_broker_demand"],
    )
    client = MetadataSchemaClient(
        index=build_metadata_column_index(dags_root=tmp_path / "dags")
    )
    sql = """
    SELECT COUNT(*) AS offers_submitted
    FROM dw_sale.fact_offers AS f
    GROUP BY f.sk_broker_supply
    ORDER BY offers_submitted DESC
    """
    errors, warnings = validate_golden_query_sql(
        sql,
        query_label="Query 3",
        client=client,
    )
    assert errors == []


def test_validate_golden_queries_iterates_all_queries(tmp_path: Path):
    _write_metadata(
        tmp_path,
        database_name="dw_visit",
        table_name="fact_visits",
        columns=["sk_visit"],
    )
    client = MetadataSchemaClient(
        index=build_metadata_column_index(dags_root=tmp_path / "dags")
    )
    queries = [
        _FakeGoldenQuery("Q1", "SELECT sk_visit FROM dw_visit.fact_visits"),
        _FakeGoldenQuery("Q2", "SELECT missing_col FROM dw_visit.fact_visits"),
    ]
    errors, _ = validate_golden_queries(queries, client=client)
    assert any("Q2" in e for e in errors)
    assert any("missing_col" in e for e in errors)


def test_validate_trino_sql_syntax_unbalanced_parenthesis_is_blocking():
    errors, warnings = validate_trino_sql_syntax(
        "SELECT sk_visit FROM dw_visit.fact_visits WHERE (id_house = 1",
        query_label="Query 1",
    )
    assert errors
    assert any(
        "unclosed parenthesis" in e or "invalid Trino SQL syntax" in e for e in errors
    )
    assert not warnings


def test_validate_trino_sql_syntax_invalid_trino_parse_is_blocking():
    errors, warnings = validate_trino_sql_syntax(
        "SELECT (sk_visit + FROM dw_visit.fact_visits",
        query_label="Query 1",
    )
    assert errors
    assert any(
        "invalid Trino SQL syntax" in e or "unclosed parenthesis" in e for e in errors
    )
    assert not warnings


def test_validate_golden_query_sql_syntax_error_skips_metadata_checks(tmp_path: Path):
    _write_metadata(
        tmp_path,
        database_name="dw_visit",
        table_name="fact_visits",
        columns=["sk_visit"],
    )
    client = MetadataSchemaClient(
        index=build_metadata_column_index(dags_root=tmp_path / "dags")
    )
    errors, warnings = validate_golden_query_sql(
        "SELECT sk_visit FROM dw_visit.fact_visits WHERE (id_house = 1",
        query_label="Query 1",
        client=client,
    )
    assert errors
    assert any(
        "invalid Trino SQL syntax" in e or "unclosed parenthesis" in e for e in errors
    )
    assert not any("not found in repo metadata" in e for e in errors)


def test_cli_main_changed_only_no_files(monkeypatch: pytest.MonkeyPatch):
    import validate_entity_golden_queries_metadata as cli

    monkeypatch.setattr(cli, "_git_changed_entity_files", lambda _branch: [])
    assert cli.main(["--changed-only", "-b", "feature/x"]) == 0
