"""Tests for declaration-level dataset_dependencies in create_dag_files."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

from bietlejuice.base.airflow.datasets.dataset_encoder import DatasetEncoder
from bietlejuice.base.dependencies.bietlejuice_redundant_dependency_finder import (
    BietlejuiceRedundantDependencyFinder,
)
from bietlejuice.services.dataset_service import DatasetService

REPO_ROOT = Path(__file__).resolve().parents[6]
SCRIPT_PATH = (
    REPO_ROOT
    / "packages/bietlejuice-compiler/scripts/ci_cd/airflow_dag_builder/create_dag_files.py"
)


@pytest.fixture(scope="module")
def create_dag_files_mod():
    spec = importlib.util.spec_from_file_location(
        "create_dag_files_dataset_deps", SCRIPT_PATH
    )
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(REPO_ROOT))
    sys.path.insert(0, str(REPO_ROOT / "packages/bietlejuice-compiler/scripts"))
    spec.loader.exec_module(mod)
    return mod


def _expected_datasets_code(dependencies: list[str]) -> str:
    datasets = DatasetService.get_dag_datasets_from_dependencies(dependencies)
    return DatasetEncoder.encode_dataset_as_python_code(datasets)


def test_read_declaration_dataset_dependencies_returns_list(
    create_dag_files_mod, tmp_path
):
    declaration = tmp_path / "sample_declaration.yml"
    declaration.write_text(
        "dag:\n"
        "  name: sample\n"
        "  dataset_dependencies:\n"
        "    - datalake_x.y:first-run-of-day\n"
    )

    result = create_dag_files_mod._read_declaration_dataset_dependencies(
        str(declaration)
    )

    assert result == ["datalake_x.y:first-run-of-day"]


def test_read_declaration_dataset_dependencies_missing_returns_none(
    create_dag_files_mod, tmp_path
):
    declaration = tmp_path / "plain_declaration.yml"
    declaration.write_text("dag:\n  name: plain\n")

    assert (
        create_dag_files_mod._read_declaration_dataset_dependencies(str(declaration))
        is None
    )


def test_read_declaration_dataset_dependencies_rejects_non_list(
    create_dag_files_mod, tmp_path
):
    declaration = tmp_path / "bad_declaration.yml"
    declaration.write_text(
        "dag:\n  name: bad\n  dataset_dependencies: datalake_x.y:first-run-of-day\n"
    )

    with pytest.raises(ValueError, match="dataset_dependencies must be a list"):
        create_dag_files_mod._read_declaration_dataset_dependencies(str(declaration))


def test_datasets_code_uses_declaration_when_missing_from_yaml(
    create_dag_files_mod, tmp_path
):
    declaration = tmp_path / "luigi_declaration.yml"
    declaration.write_text(
        "dag:\n"
        "  name: enrich_luigijr_test\n"
        "  dataset_dependencies:\n"
        "    - datalake_dag_inventory_clean.dag:first-run-of-day\n"
    )
    finder = BietlejuiceRedundantDependencyFinder({})

    code = create_dag_files_mod._datasets_code(
        "enrich_luigijr_test",
        {},
        finder,
        str(declaration),
    )

    assert code == _expected_datasets_code(
        ["datalake_dag_inventory_clean.dag:first-run-of-day"]
    )


def test_datasets_code_prefers_dependencies_yaml_over_declaration(
    create_dag_files_mod, tmp_path
):
    declaration = tmp_path / "mixed_declaration.yml"
    declaration.write_text(
        "dag:\n"
        "  name: mixed\n"
        "  dataset_dependencies:\n"
        "    - datalake_from_declaration.table:first-run-of-day\n"
    )
    dependencies = {
        "bietlejuice.mixed": ["bietlejuice.upstream:load-clean-table:first-run-of-day"]
    }
    finder = BietlejuiceRedundantDependencyFinder(dependencies)

    code = create_dag_files_mod._datasets_code(
        "mixed",
        dependencies,
        finder,
        str(declaration),
    )

    assert code == _expected_datasets_code(
        ["bietlejuice.upstream:load-clean-table:first-run-of-day"]
    )


def test_datasets_code_returns_none_without_yaml_or_declaration_deps(
    create_dag_files_mod, tmp_path
):
    declaration = tmp_path / "cron_declaration.yml"
    declaration.write_text("dag:\n  name: cron_only\n  schedule_interval: 0 8 * * *\n")
    finder = BietlejuiceRedundantDependencyFinder({})

    code = create_dag_files_mod._datasets_code(
        "cron_only",
        {},
        finder,
        str(declaration),
    )

    assert code == "None"


def test_create_dag_files_writes_declaration_datasets(
    create_dag_files_mod, monkeypatch, tmp_path
):
    dags_root = tmp_path / "dags"
    dag_dir = dags_root / "luigijr" / "enrich_luigijr_sample"
    dag_dir.mkdir(parents=True)
    (dag_dir / "enrich_luigijr_sample_declaration.yml").write_text(
        "dag:\n"
        "  name: enrich_luigijr_sample\n"
        "  schedule_interval: null\n"
        "  dataset_dependencies:\n"
        "    - datalake_dag_inventory_clean.dag:first-run-of-day\n"
    )

    monkeypatch.setattr(create_dag_files_mod, "DAG_PACKAGES_ROOT", str(dags_root))
    monkeypatch.setattr(
        create_dag_files_mod.BietlejuiceDependencyHelper,
        "read_dependencies",
        lambda: {},
    )

    create_dag_files_mod.create_dag_files(
        dag_name_glob="enrich_luigijr_sample",
        include_dir="luigijr",
    )

    dag_py = (dag_dir / "enrich_luigijr_sample_dag.py").read_text()
    expected = _expected_datasets_code(
        ["datalake_dag_inventory_clean.dag:first-run-of-day"]
    )
    assert f"datasets = {expected}" in dag_py
