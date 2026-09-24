"""Scheduling tier is the highest effective tier downstream."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[6]
SCRIPT_PATH = (
    REPO_ROOT
    / "packages/bietlejuice-compiler/scripts/ci_cd/airflow_dag_builder/create_dag_files.py"
)


@pytest.fixture(scope="module")
def create_dag_files_mod():
    spec = importlib.util.spec_from_file_location(
        "create_dag_files_priority_tiers", SCRIPT_PATH
    )
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(REPO_ROOT))
    sys.path.insert(0, str(REPO_ROOT / "packages/bietlejuice-compiler/scripts"))
    spec.loader.exec_module(mod)
    return mod


def _write_declaration(dags_root: Path, name: str, body: str) -> None:
    folder = dags_root / "growth" / name
    folder.mkdir(parents=True)
    (folder / f"{name}_declaration.yml").write_text(body)


def test_priority_tier_is_the_highest_tier_downstream(
    create_dag_files_mod, monkeypatch, tmp_path
):
    dags_root = tmp_path / "dags"
    _write_declaration(dags_root, "root", "dag:\n  name: root\n")
    _write_declaration(dags_root, "source", "dag:\n  name: source\n")
    _write_declaration(
        dags_root,
        "mixed",
        "dag:\n"
        "  name: mixed\n"
        "  criticality: High\n"
        "workflow:\n"
        "  tables_customization:\n"
        "    fact_x:\n"
        "      criticality: Critical\n",
    )
    _write_declaration(dags_root, "leaf", "dag:\n  name: leaf\n  criticality: Low\n")
    _write_declaration(dags_root, "feeder", "dag:\n  name: feeder\n")
    _write_declaration(
        dags_root,
        "high_only",
        "dag:\n  name: high_only\n  criticality: High\n",
    )
    dependencies = {
        "bietlejuice.source": ["bietlejuice.root:load-raw-z"],
        "bietlejuice.mixed": ["bietlejuice.source:load-clean-x:first-run-of-day"],
        "bietlejuice.leaf": ["bietlejuice.mixed:load-dw-fact-x"],
        "bietlejuice.high_only": [{"any": ["bietlejuice.feeder:load-clean-y"]}],
    }
    monkeypatch.setattr(create_dag_files_mod, "DAG_PACKAGES_ROOT", str(dags_root))

    assert create_dag_files_mod._priority_tiers(dependencies) == {
        "root": "Critical",
        "source": "Critical",
        "mixed": "Critical",
        "leaf": "Low",
        "feeder": "High",
        "high_only": "High",
    }
