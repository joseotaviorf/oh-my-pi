# -*- coding: utf-8 -*-
"""Tests for SQL table extraction (future DW / SQL DAG profiles)."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from scripts.ci_cd.source_layer_validation.sql_table_extractor import (  # noqa: E402
    extract_table_fqns_from_sql_files,
    extract_table_fqns_from_sql_text,
    normalize_sql_for_table_extraction,
)


def test_extract_from_select_join():
    sql = """
    SELECT a.x
    FROM datalake_ebdb_clean.contract AS a
    JOIN dw_rent.dim_contract AS d ON a.id = d.sk
    """
    tables = extract_table_fqns_from_sql_text(sql)
    assert tables == {"datalake_ebdb_clean.contract", "dw_rent.dim_contract"}


def test_extract_insert_into():
    sql = """
    INSERT INTO metric_rent.summary
    SELECT id FROM datalake_ebdb_clean.listing
    """
    tables = extract_table_fqns_from_sql_text(sql)
    assert "datalake_ebdb_clean.listing" in tables
    assert "metric_rent.summary" in tables


def test_cte_inner_table_still_found():
    sql = """
    WITH c AS (SELECT id FROM datalake_ebdb_clean.house)
    SELECT * FROM c
    """
    tables = extract_table_fqns_from_sql_text(sql)
    assert tables == {"datalake_ebdb_clean.house"}


def test_bare_table_name_skipped():
    sql = "SELECT * FROM only_name"
    tables = extract_table_fqns_from_sql_text(sql)
    assert tables == set()


def test_extract_from_sql_files_glob(tmp_path):
    q = tmp_path / "queries" / "dw"
    q.mkdir(parents=True)
    (q / "foo.sql").write_text("SELECT * FROM datalake_ebdb_clean.x", encoding="utf-8")
    tables = extract_table_fqns_from_sql_files(
        tmp_path, ["queries/dw/*.sql"], dialect="spark"
    )
    assert tables == {"datalake_ebdb_clean.x"}


def test_bracket_param_normalized():
    # Avoid nested quotes (DATE('{x}') would become DATE(''DUMMY'') after replace)
    sql = "SELECT * FROM datalake_ebdb_clean.t WHERE d >= {load_start_date}"
    norm = normalize_sql_for_table_extraction(sql)
    assert "{load_start_date}" not in norm
    tables = extract_table_fqns_from_sql_text(sql)
    assert "datalake_ebdb_clean.t" in tables


def test_extract_all_tables_merges_sql_when_profile_has_globs():
    from scripts.ci_cd.source_layer_validation.dag_reference_extractors import (
        extract_all_tables_for_core_dag,
    )

    root = Path(__file__).resolve().parents[4] / "dags" / "core" / "core_region"
    if not root.is_dir():
        pytest.skip("core_region DAG not present")

    profile_min = {
        "yaml_conf_files": [],
        "spark_jobs_subdir": "spark_jobs",
        "skip_yaml_keys": [],
        "scan_python_spark_table_literals": False,
        "sql_scan_globs": ["queries/**/*.sql"],
        "sql_read_dialect": "spark",
    }
    # core_region may have no queries/**/*.sql; still should not raise
    tables = extract_all_tables_for_core_dag(profile_min, root)
    assert isinstance(tables, set)
