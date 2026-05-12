"""Strict vs lenient behavior for source-layer validation."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[6]))

from scripts.ci_cd.source_layer_validation.validate_source_layer_policy import (  # noqa: E402
    load_profile,
    run_validation,
)


@pytest.fixture
def dags_profile():
    return load_profile("dags")


def _write_enrich_dag_with_sql(tmp_path, sql_from_raw=False):
    monkey_root = tmp_path
    dag = monkey_root / "dags/domain/policy_dag"
    (dag / "queries/clean").mkdir(parents=True)
    (dag / "policy_dag_declaration.yml").write_text(
        "dag:\n  name: policy_dag\nworkflow:\n  type: query_delta\n  layer: enrich\n",
        encoding="utf-8",
    )
    tbl = "datalake_ebdb_raw.bad" if sql_from_raw else "datalake_ebdb_clean.ok"
    (dag / "queries/clean/q.sql").write_text(
        f"SELECT 1 AS x FROM {tbl}", encoding="utf-8"
    )
    return "dags/domain/policy_dag", "dags/domain/policy_dag/queries/clean/q.sql"


def test_strict_fails_when_new_sql_uses_raw(dags_profile, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    dag_root, sql_path = _write_enrich_dag_with_sql(tmp_path, sql_from_raw=True)
    changed = {sql_path: "A"}
    ok, _warn = run_validation([dag_root], dags_profile, False, changed)
    assert ok is False


def test_strict_passes_when_new_sql_uses_only_clean(
    dags_profile, tmp_path, monkeypatch
):
    monkeypatch.chdir(tmp_path)
    dag_root, sql_path = _write_enrich_dag_with_sql(tmp_path, sql_from_raw=False)
    changed = {sql_path: "A"}
    ok, warn = run_validation([dag_root], dags_profile, False, changed)
    assert ok is True
    assert warn is False


def test_lenient_warns_but_passes_on_modified_sql_violation(
    dags_profile, tmp_path, monkeypatch, capsys
):
    monkeypatch.chdir(tmp_path)
    dag_root, sql_path = _write_enrich_dag_with_sql(tmp_path, sql_from_raw=True)
    changed = {sql_path: "M"}
    ok, warn = run_validation([dag_root], dags_profile, False, changed)
    assert ok is True
    assert warn is True
    out = capsys.readouterr().out
    assert "⚠️ Source validation passed with a warning" in out
    assert "Invalid table usage in **edited** files:" in out
    assert "Table with error:" in out


def test_metadata_only_change_lenient_warns_if_dag_has_violation(
    dags_profile, tmp_path, monkeypatch, capsys
):
    monkeypatch.chdir(tmp_path)
    dag_root, sql_path = _write_enrich_dag_with_sql(tmp_path, sql_from_raw=True)
    (Path(tmp_path) / dag_root / "metadata/enrich").mkdir(parents=True)
    meta = Path(tmp_path) / dag_root / "metadata/enrich/x.yml"
    meta.write_text("x: 1\n", encoding="utf-8")
    rel_meta = "dags/domain/policy_dag/metadata/enrich/x.yml"
    changed = {rel_meta: "M"}
    ok, warn = run_validation([dag_root], dags_profile, False, changed)
    assert ok is True
    assert warn is True
    out = capsys.readouterr().out
    assert "⚠️ Source validation passed with a warning" in out


def test_skip_workflow_type_returns_ok(dags_profile, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    dag = tmp_path / "dags/domain/cdc_dag"
    dag.mkdir(parents=True)
    (dag / "cdc_dag_declaration.yml").write_text(
        "dag:\n  name: cdc_dag\nworkflow:\n  type: cdc\n  layer: raw\n",
        encoding="utf-8",
    )
    rel = "dags/domain/cdc_dag/cdc_dag_declaration.yml"
    ok, _warn = run_validation(["dags/domain/cdc_dag"], dags_profile, False, {rel: "A"})
    assert ok is True


def test_strict_new_file_ok_full_dag_legacy_warns(
    dags_profile, tmp_path, monkeypatch, capsys
):
    monkeypatch.chdir(tmp_path)
    dag = tmp_path / "dags/domain/mixed"
    (dag / "queries/clean").mkdir(parents=True)
    (dag / "mixed_declaration.yml").write_text(
        "dag:\n  name: mixed\nworkflow:\n  type: query_delta\n  layer: enrich\n",
        encoding="utf-8",
    )
    (dag / "queries/clean/bad.sql").write_text(
        "SELECT 1 FROM datalake_ebdb_raw.x", encoding="utf-8"
    )
    (dag / "queries/clean/good.sql").write_text(
        "SELECT 1 FROM datalake_ebdb_clean.h", encoding="utf-8"
    )
    changed = {"dags/domain/mixed/queries/clean/good.sql": "A"}
    ok, warn = run_validation(["dags/domain/mixed"], dags_profile, False, changed)
    assert ok is True
    assert warn is True
    out = capsys.readouterr().out
    assert "⚠️ Source validation passed with a warning" in out
    assert "Invalid table usage in **edited** files:" in out


def test_strict_fail_then_warn_prints_failure_before_warning(
    dags_profile, tmp_path, monkeypatch, capsys
):
    """Example 7: new file violates policy; legacy file also violates — exit 1, order fail then warn."""
    monkeypatch.chdir(tmp_path)
    dag = tmp_path / "dags/domain/mixed2"
    (dag / "queries/clean").mkdir(parents=True)
    (dag / "mixed2_declaration.yml").write_text(
        "dag:\n  name: mixed2\nworkflow:\n  type: query_delta\n  layer: enrich\n",
        encoding="utf-8",
    )
    (dag / "queries/clean/old.sql").write_text(
        "SELECT 1 FROM datalake_ebdb_raw.legacy", encoding="utf-8"
    )
    (dag / "queries/clean/new.sql").write_text(
        "SELECT 1 FROM datalake_ebdb_raw.badnew", encoding="utf-8"
    )
    changed = {"dags/domain/mixed2/queries/clean/new.sql": "A"}
    ok, warn = run_validation(["dags/domain/mixed2"], dags_profile, False, changed)
    assert ok is False
    assert warn is True
    out = capsys.readouterr().out
    fail_pos = out.find("❌ Source validation failed")
    warn_pos = out.find("⚠️ Source validation passed with a warning")
    assert fail_pos != -1 and warn_pos != -1 and fail_pos < warn_pos
