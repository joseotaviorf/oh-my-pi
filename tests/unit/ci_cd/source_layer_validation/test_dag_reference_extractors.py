# -*- coding: utf-8 -*-
"""Tests for DAG table reference extractors (YAML conf, Python literals, SQL globs)."""

import sys
import tempfile
from pathlib import Path

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from scripts.ci_cd.source_layer_validation.dag_reference_extractors import (  # noqa: E402
    extract_all_tables_for_core_dag,
    extract_tables_by_source_file,
    extract_tables_from_python_literals,
    extract_tables_from_spark_confs,
)


@pytest.fixture
def minimal_profile():
    return {
        "spark_jobs_subdir": "spark_jobs",
        "yaml_conf_files": ["prod_conf.yml", "forno_conf.yml"],
        "skip_yaml_keys": ["merge_on", "ENTITY_TYPE", "when_matched_update_condition"],
        "scan_python_spark_table_literals": True,
        "python_globs": ["load_*.py", "*_base.py"],
    }


def test_extract_yaml_skips_merge_on_and_entity_type(minimal_profile):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        sj = root / "spark_jobs"
        sj.mkdir()
        conf = {
            "ENTITY_TYPE": "FOO",
            "merge_on": ["sk_x"],
            "T1": "datalake_ebdb_clean.a",
            "T2": "core_listing.b",
        }
        with open(sj / "prod_conf.yml", "w") as f:
            yaml.dump(conf, f)

        tables = extract_tables_from_spark_confs(
            root,
            minimal_profile["yaml_conf_files"],
            minimal_profile["spark_jobs_subdir"],
            minimal_profile["skip_yaml_keys"],
        )
        assert tables == {"datalake_ebdb_clean.a", "core_listing.b"}


def test_extract_python_literals():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        sj = root / "spark_jobs"
        sj.mkdir()
        (sj / "load_core_x.py").write_text(
            'x = spark.table("datalake_ebdb_clean.foo")\n'
            "y = spark.table( 'core_listing.bar' )\n",
            encoding="utf-8",
        )
        tables = extract_tables_from_python_literals(root, "spark_jobs", ["load_*.py"])
        assert tables == {"datalake_ebdb_clean.foo", "core_listing.bar"}


def test_extract_tables_by_source_file_splits_sql_per_path(
    minimal_profile, tmp_path, monkeypatch
):
    monkeypatch.chdir(tmp_path)
    root = Path(tmp_path) / "dags/domain/x"
    (root / "queries/clean").mkdir(parents=True)
    (root / "queries/clean/a.sql").write_text(
        "SELECT 1 FROM datalake_ebdb_clean.t1", encoding="utf-8"
    )
    (root / "queries/clean/b.sql").write_text(
        "SELECT 1 FROM datalake_ebdb_clean.t2", encoding="utf-8"
    )
    profile = {
        "sql_scan_globs": ["queries/**/*.sql"],
        "sql_read_dialect": "spark",
        "spark_jobs_subdir": "spark_jobs",
        "yaml_conf_files": [],
        "skip_yaml_keys": [],
        "scan_python_spark_table_literals": False,
        "python_globs": ["load_*.py"],
    }
    by_file = extract_tables_by_source_file(profile, root, "query_delta")
    assert len(by_file) == 2
    assert by_file["dags/domain/x/queries/clean/a.sql"] == {"datalake_ebdb_clean.t1"}
    assert by_file["dags/domain/x/queries/clean/b.sql"] == {"datalake_ebdb_clean.t2"}


def test_extract_all_tables_for_core_dag(minimal_profile):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        sj = root / "spark_jobs"
        sj.mkdir()
        with open(sj / "prod_conf.yml", "w") as f:
            yaml.dump({"X": "datalake_ebdb_clean.t"}, f)
        (sj / "load_x.py").write_text('spark.table("dw_rent.fact")\n', encoding="utf-8")
        all_t = extract_all_tables_for_core_dag(minimal_profile, root)
        assert all_t == {"datalake_ebdb_clean.t", "dw_rent.fact"}
