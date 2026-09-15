"""Unit tests for validate_people_data_quality_files_exist."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from scripts.ci_cd.people_domain_scope import dq_path_for_artifact, requires_dq_file
from scripts.ci_cd.validate_people_data_quality_files_exist import (  # noqa: E402
    collect_artifact_paths,
)


def test_requires_dq_for_clean_layer():
    assert requires_dq_file("dags/people/pin/queries/clean/foo.sql")


def test_requires_dq_for_enterprise_efficiency_clean_layer():
    assert requires_dq_file(
        "dags/enterprise_efficiency/claude_usage_api/queries/clean/foo.sql"
    )


def test_skips_reverse_layer():
    assert not requires_dq_file("dags/people/reverse_reports/queries/reverse/foo.sql")


def test_skips_raw_layer():
    assert not requires_dq_file("dags/people/pin/queries/raw/foo.sql")


def test_skips_non_scoped_domain():
    assert not requires_dq_file("dags/growth/foo/queries/clean/foo.sql")


def test_dq_path_resolution(tmp_path: Path):
    sql = tmp_path / "dags/people/pin/queries/clean/my_table.sql"
    sql.parent.mkdir(parents=True, exist_ok=True)
    sql.write_text("SELECT 1", encoding="utf-8")
    dq_path = dq_path_for_artifact(str(sql))
    assert dq_path == Path("dags/people/pin/data_quality/clean/my_table.yml")


def test_dq_path_resolution_enterprise_efficiency(tmp_path: Path):
    sql = tmp_path / (
        "dags/enterprise_efficiency/claude_usage_api/queries/clean/my_table.sql"
    )
    sql.parent.mkdir(parents=True, exist_ok=True)
    sql.write_text("SELECT 1", encoding="utf-8")
    dq_path = dq_path_for_artifact(str(sql))
    assert dq_path == Path(
        "dags/enterprise_efficiency/claude_usage_api/data_quality/clean/my_table.yml"
    )


def test_collect_paths_mode_lists_clean_enrich_only(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    clean_sql = tmp_path / "dags/people/pin/queries/clean/a.sql"
    reverse_sql = tmp_path / "dags/people/reverse_reports/queries/reverse/b.sql"
    clean_sql.parent.mkdir(parents=True, exist_ok=True)
    reverse_sql.parent.mkdir(parents=True, exist_ok=True)
    clean_sql.write_text("SELECT 1", encoding="utf-8")
    reverse_sql.write_text("SELECT 1", encoding="utf-8")

    monkeypatch.chdir(tmp_path)
    artifacts = collect_artifact_paths("paths", True, paths=["dags/people"])
    normalized = {a.replace("\\", "/") for a in artifacts}
    assert "dags/people/pin/queries/clean/a.sql" in normalized
    assert "dags/people/reverse_reports/queries/reverse/b.sql" in normalized


def test_missing_dq_detected(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    sql = tmp_path / "dags/people/pin/queries/clean/missing_dq.sql"
    sql.parent.mkdir(parents=True, exist_ok=True)
    sql.write_text("SELECT 1", encoding="utf-8")
    monkeypatch.chdir(tmp_path)

    from scripts.ci_cd.validate_people_data_quality_files_exist import main

    monkeypatch.setattr(
        "sys.argv",
        ["validate_people_data_quality_files_exist.py", "--paths", "dags/people/pin"],
    )
    assert main() == 1


def test_paths_mode_fails_when_no_valid_artifacts(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    reverse_sql = tmp_path / "dags/people/reverse_reports/queries/reverse/b.sql"
    reverse_sql.parent.mkdir(parents=True, exist_ok=True)
    reverse_sql.write_text("SELECT 1", encoding="utf-8")
    monkeypatch.chdir(tmp_path)

    from scripts.ci_cd.validate_people_data_quality_files_exist import main

    monkeypatch.setattr(
        "sys.argv",
        [
            "validate_people_data_quality_files_exist.py",
            "--paths",
            "dags/people/reverse_reports",
        ],
    )
    assert main() == 1
