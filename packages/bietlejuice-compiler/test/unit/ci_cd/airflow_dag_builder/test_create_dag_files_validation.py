"""Tests for create_dag_files validation-twin codegen."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest
from airflow.models.dag import DAG
from airflow.models.dagbag import DagBag

REPO_ROOT = Path(__file__).resolve().parents[6]
SCRIPT_PATH = (
    REPO_ROOT
    / "packages/bietlejuice-compiler/scripts/ci_cd/airflow_dag_builder/create_dag_files.py"
)


@pytest.fixture(scope="module")
def create_dag_files_mod():
    # scripts/ lives on PYTHONPATH via compiler package layout; load by path to
    # avoid executing CLI when the module is imported elsewhere.
    spec = importlib.util.spec_from_file_location(
        "create_dag_files_under_test", SCRIPT_PATH
    )
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    # Ensure `from scripts import SCRIPTS_PATH` / `from dags import ...` resolve.
    sys.path.insert(0, str(REPO_ROOT))
    sys.path.insert(0, str(REPO_ROOT / "packages/bietlejuice-compiler/scripts"))
    try:
        spec.loader.exec_module(mod)
    finally:
        # Leave paths for subsequent imports; tests run in-process.
        pass
    return mod


def test_has_validation_cluster_true_from_cluster_yml(create_dag_files_mod, tmp_path):
    dag_dir = tmp_path / "sample_dag"
    dag_dir.mkdir()
    (dag_dir / "sample_dag_declaration.yml").write_text(
        "dag:\n  name: sample_dag\nworkflow:\n  type: query_delta\n  layer: clean\n"
    )
    (dag_dir / "sample_dag_cluster.yml").write_text(
        "cluster:\n  type: xs\nvalidation:\n  cluster:\n    type: xs\n"
    )
    assert (
        create_dag_files_mod.has_validation_cluster(str(dag_dir), "sample_dag") is True
    )


def test_has_validation_cluster_true_from_declaration(create_dag_files_mod, tmp_path):
    dag_dir = tmp_path / "inline_val"
    dag_dir.mkdir()
    (dag_dir / "inline_val_declaration.yml").write_text(
        "dag:\n  name: inline_val\n"
        "workflow:\n  type: query_delta\n  layer: clean\n"
        "validation:\n  cluster:\n    type: xs\n"
    )
    assert (
        create_dag_files_mod.has_validation_cluster(str(dag_dir), "inline_val") is True
    )


def test_cluster_file_validation_takes_precedence(create_dag_files_mod, tmp_path):
    dag_dir = tmp_path / "precedence"
    dag_dir.mkdir()
    (dag_dir / "precedence_declaration.yml").write_text(
        "dag:\n  name: precedence\n"
        "workflow:\n  type: query_delta\n  layer: clean\n"
        "validation:\n  cluster:\n    type: inline\n"
    )
    (dag_dir / "precedence_cluster.yml").write_text(
        "cluster:\n  type: prod\nvalidation:\n  description: no validation cluster\n"
    )
    assert (
        create_dag_files_mod.has_validation_cluster(str(dag_dir), "precedence") is False
    )


def test_malformed_cluster_file_fails_during_codegen(create_dag_files_mod, tmp_path):
    dag_dir = tmp_path / "malformed"
    dag_dir.mkdir()
    (dag_dir / "malformed_declaration.yml").write_text(
        "dag:\n  name: malformed\nworkflow:\n  type: query_delta\n  layer: clean\n"
    )
    (dag_dir / "malformed_cluster.yml").write_text(
        "validation:\n  cluster:\n    type: xs\n"
    )
    with pytest.raises(AssertionError, match="top-level 'cluster' key"):
        create_dag_files_mod.has_validation_cluster(str(dag_dir), "malformed")


def test_has_validation_cluster_false_without_block(create_dag_files_mod, tmp_path):
    dag_dir = tmp_path / "plain"
    dag_dir.mkdir()
    (dag_dir / "plain_declaration.yml").write_text(
        "dag:\n  name: plain\nworkflow:\n  type: query_delta\n  layer: clean\n"
    )
    (dag_dir / "plain_cluster.yml").write_text("cluster:\n  type: xs\n")
    assert create_dag_files_mod.has_validation_cluster(str(dag_dir), "plain") is False


def test_main_template_has_no_validation_twin():
    template = (
        REPO_ROOT
        / "packages/bietlejuice-compiler/scripts/ci_cd/airflow_dag_builder/__dags_template__.py"
    ).read_text()
    assert "is_validation=True" not in template
    assert "validation_dag" not in template


def test_validation_template_builds_validation_dag():
    template = (
        REPO_ROOT
        / "packages/bietlejuice-compiler/scripts/ci_cd/airflow_dag_builder/__validation_dags_template__.py"
    ).read_text()
    assert "is_validation=True" in template
    assert "validation_dag =" in template


def _write_declaration(root: Path, domain: str, dag_name: str) -> None:
    dag_dir = root / domain / dag_name
    dag_dir.mkdir(parents=True)
    (dag_dir / f"{dag_name}_declaration.yml").write_text("dag: {}\n")


def test_create_domain_bundles_chunks_and_writes_exact_excludes(
    create_dag_files_mod, monkeypatch, tmp_path
):
    dags_root = tmp_path / "dags"
    _write_declaration(dags_root, "growth", "dag_a")
    _write_declaration(dags_root, "growth", "dag_b")
    output_dir = dags_root / "_astro_bundles"
    exclude_file = tmp_path / "generated-dag-excludes.txt"

    monkeypatch.setattr(create_dag_files_mod, "DAG_PACKAGES_ROOT", str(dags_root))
    monkeypatch.setattr(create_dag_files_mod, "_datasets_code", lambda *_args: "None")
    monkeypatch.setattr(
        create_dag_files_mod.BietlejuiceDependencyHelper,
        "read_dependencies",
        lambda: {},
    )

    bundles = create_dag_files_mod.create_domain_bundles(
        max_dags_per_bundle=1,
        output_dir=str(output_dir),
        exclude_file=str(exclude_file),
    )

    assert [Path(bundle).name for bundle in bundles] == [
        "_bundle_01.py",
        "_bundle_02.py",
    ]
    assert exclude_file.read_text().splitlines() == [
        "growth/dag_a/dag_a_dag.py",
        "growth/dag_b/dag_b_dag.py",
    ]
    assert "('dag_a', None, 'Medium')" in Path(bundles[0]).read_text()
    assert "('dag_b', None, 'Medium')" in Path(bundles[1]).read_text()


def test_generated_bundle_loads_all_dags_with_stable_ids(
    create_dag_files_mod, monkeypatch, tmp_path
):
    import bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser as parser_module
    import bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher as dispatcher_module

    dags_root = tmp_path / "dags"
    _write_declaration(dags_root, "growth", "dag_a")
    _write_declaration(dags_root, "growth", "dag_b")
    monkeypatch.setattr(create_dag_files_mod, "DAG_PACKAGES_ROOT", str(dags_root))
    monkeypatch.setattr(create_dag_files_mod, "_datasets_code", lambda *_args: "None")
    monkeypatch.setattr(
        create_dag_files_mod.BietlejuiceDependencyHelper,
        "read_dependencies",
        lambda: {},
    )

    class FakeParser:
        def __init__(self, dag_name):
            self.dag_name = dag_name

        def dag_declaration(self):
            return {
                "dag": {"name": self.dag_name},
                "workflow": {"layer": "clean"},
                "cluster": {},
            }

    class FakeWorkflow:
        def __init__(self, dag_name):
            self.dag_name = dag_name

        def build_dag(self):
            return DAG(dag_id=f"bietlejuice.{self.dag_name}")

    class FakeFactory:
        def __init__(self, dag_name):
            self.dag_name = dag_name

        def get_workflow(self):
            return FakeWorkflow(self.dag_name)

    class FakeDispatcher:
        def __init__(self, layer):
            self.layer = layer

        def get_factory(self, **kwargs):
            return FakeFactory(kwargs["dag_args"]["name"])

    monkeypatch.setattr(parser_module, "DAGYamlParser", FakeParser)
    monkeypatch.setattr(dispatcher_module, "FactoryDispatcher", FakeDispatcher)

    bundles = create_dag_files_mod.create_domain_bundles(
        output_dir=str(dags_root / "_astro_bundles"),
        exclude_file=str(tmp_path / "excludes.txt"),
    )
    dagbag = DagBag(dag_folder=bundles[0], include_examples=False, safe_mode=False)

    assert not dagbag.import_errors
    assert set(dagbag.dags) == {"bietlejuice.dag_a", "bietlejuice.dag_b"}


def test_generated_bundle_quarantines_build_failures(
    create_dag_files_mod, monkeypatch, tmp_path
):
    import bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser as parser_module

    dags_root = tmp_path / "dags"
    _write_declaration(dags_root, "growth", "broken_a")
    _write_declaration(dags_root, "growth", "broken_b")
    monkeypatch.setattr(create_dag_files_mod, "DAG_PACKAGES_ROOT", str(dags_root))
    monkeypatch.setattr(create_dag_files_mod, "_datasets_code", lambda *_args: "None")
    monkeypatch.setattr(
        create_dag_files_mod.BietlejuiceDependencyHelper,
        "read_dependencies",
        lambda: {},
    )

    class BrokenParser:
        def __init__(self, dag_name):
            raise ValueError(f"invalid {dag_name}")

    monkeypatch.setattr(parser_module, "DAGYamlParser", BrokenParser)
    bundles = create_dag_files_mod.create_domain_bundles(
        output_dir=str(dags_root / "_astro_bundles"),
        exclude_file=str(tmp_path / "excludes.txt"),
    )
    dagbag = DagBag(dag_folder=bundles[0], include_examples=False, safe_mode=False)

    assert not dagbag.import_errors, dagbag.import_errors
    assert set(dagbag.dags) == {"bietlejuice.broken_a", "bietlejuice.broken_b"}
    assert "broken-dag" in dagbag.dags["bietlejuice.broken_a"].tags
    assert "invalid broken_a" in dagbag.dags["bietlejuice.broken_a"].doc_md


def test_generated_bundle_keeps_healthy_dags_when_one_fails(
    create_dag_files_mod, monkeypatch, tmp_path
):
    """One broken declaration must not remove a healthy sibling from the bag."""
    import bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser as parser_module
    import bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher as dispatcher_module

    dags_root = tmp_path / "dags"
    _write_declaration(dags_root, "growth", "healthy")
    _write_declaration(dags_root, "growth", "broken")
    monkeypatch.setattr(create_dag_files_mod, "DAG_PACKAGES_ROOT", str(dags_root))
    monkeypatch.setattr(create_dag_files_mod, "_datasets_code", lambda *_args: "None")
    monkeypatch.setattr(
        create_dag_files_mod.BietlejuiceDependencyHelper,
        "read_dependencies",
        lambda: {},
    )

    class SelectiveParser:
        def __init__(self, dag_name):
            self.dag_name = dag_name

        def dag_declaration(self):
            if self.dag_name == "broken":
                raise ValueError("invalid broken")
            return {
                "dag": {"name": self.dag_name},
                "workflow": {"layer": "clean"},
                "cluster": {},
            }

    class FakeWorkflow:
        def __init__(self, dag_name):
            self.dag_name = dag_name

        def build_dag(self):
            return DAG(dag_id=f"bietlejuice.{self.dag_name}")

    class FakeFactory:
        def __init__(self, dag_name):
            self.dag_name = dag_name

        def get_workflow(self):
            return FakeWorkflow(self.dag_name)

    class FakeDispatcher:
        def __init__(self, layer):
            self.layer = layer

        def get_factory(self, **kwargs):
            return FakeFactory(kwargs["dag_args"]["name"])

    monkeypatch.setattr(parser_module, "DAGYamlParser", SelectiveParser)
    monkeypatch.setattr(dispatcher_module, "FactoryDispatcher", FakeDispatcher)

    bundles = create_dag_files_mod.create_domain_bundles(
        output_dir=str(dags_root / "_astro_bundles"),
        exclude_file=str(tmp_path / "excludes.txt"),
    )
    dagbag = DagBag(dag_folder=bundles[0], include_examples=False, safe_mode=False)

    assert not dagbag.import_errors, dagbag.import_errors
    assert set(dagbag.dags) == {"bietlejuice.healthy", "bietlejuice.broken"}
    assert "broken-dag" not in dagbag.dags["bietlejuice.healthy"].tags
    assert "broken-dag" in dagbag.dags["bietlejuice.broken"].tags


def _write_validation_declaration(root: Path, domain: str, dag_name: str) -> None:
    """Declaration whose cluster file resolves a validation block."""
    dag_dir = root / domain / dag_name
    dag_dir.mkdir(parents=True)
    (dag_dir / f"{dag_name}_declaration.yml").write_text(
        f"dag:\n  name: {dag_name}\nworkflow:\n  type: query_delta\n  layer: clean\n"
    )
    (dag_dir / f"{dag_name}_cluster.yml").write_text(
        "cluster:\n  type: xs\nvalidation:\n  cluster:\n    type: xs\n"
    )


def _bundle_names(bundles: list[str]) -> list[str]:
    return [Path(bundle).name for bundle in bundles]


def _only_validation_bundle(bundles: list[str]) -> str:
    """Pick the validation bundle by file name — tmp_path itself can contain
    "_validation_bundle_" because pytest names it after the test function."""
    return next(
        bundle
        for bundle in bundles
        if Path(bundle).name.startswith("_validation_bundle_")
    )


def _patch_bundle_deps(create_dag_files_mod, monkeypatch, dags_root: Path) -> None:
    monkeypatch.setattr(create_dag_files_mod, "DAG_PACKAGES_ROOT", str(dags_root))
    monkeypatch.setattr(create_dag_files_mod, "_datasets_code", lambda *_args: "None")
    monkeypatch.setattr(
        create_dag_files_mod.BietlejuiceDependencyHelper,
        "read_dependencies",
        lambda: {},
    )


def test_domain_bundles_skip_validation_by_default(
    create_dag_files_mod, monkeypatch, tmp_path
):
    dags_root = tmp_path / "dags"
    _write_validation_declaration(dags_root, "people", "dw_employee")
    _patch_bundle_deps(create_dag_files_mod, monkeypatch, dags_root)

    bundles = create_dag_files_mod.create_domain_bundles(
        output_dir=str(dags_root / "_astro_bundles"),
        exclude_file=str(tmp_path / "excludes.txt"),
    )

    assert _bundle_names(bundles) == ["_bundle_01.py"]
    assert "_IS_VALIDATION = False" in Path(bundles[0]).read_text()


def test_include_validation_emits_separate_bundles(
    create_dag_files_mod, monkeypatch, tmp_path
):
    dags_root = tmp_path / "dags"
    _write_validation_declaration(dags_root, "people", "dw_employee")
    # Same domain, no validation block → production bundle only.
    _write_declaration(dags_root, "people", "dw_people")
    _patch_bundle_deps(create_dag_files_mod, monkeypatch, dags_root)

    bundles = create_dag_files_mod.create_domain_bundles(
        output_dir=str(dags_root / "_astro_bundles"),
        exclude_file=str(tmp_path / "excludes.txt"),
        include_validation=True,
    )

    assert _bundle_names(bundles) == ["_bundle_01.py", "_validation_bundle_01.py"]
    production = Path(bundles[0]).read_text()
    validation = Path(bundles[1]).read_text()
    assert "_IS_VALIDATION = False" in production
    assert "('dw_employee', None, 'Medium')" in production
    assert "('dw_people', None, 'Medium')" in production
    # Only the DAG with a validation.cluster reaches the validation bundle.
    assert "_IS_VALIDATION = True" in validation
    assert "('dw_employee', None, None)" in validation
    assert "dw_people" not in validation


def test_validation_bundles_are_cleaned_when_flag_is_off(
    create_dag_files_mod, monkeypatch, tmp_path
):
    """A forno/dev run must evict validation bundles a prod run left behind."""
    dags_root = tmp_path / "dags"
    _write_validation_declaration(dags_root, "people", "dw_employee")
    _patch_bundle_deps(create_dag_files_mod, monkeypatch, dags_root)
    output_dir = dags_root / "_astro_bundles"

    with_validation = create_dag_files_mod.create_domain_bundles(
        output_dir=str(output_dir),
        exclude_file=str(tmp_path / "excludes.txt"),
        include_validation=True,
    )
    assert Path(with_validation[1]).exists()

    create_dag_files_mod.create_domain_bundles(
        output_dir=str(output_dir),
        exclude_file=str(tmp_path / "excludes.txt"),
    )

    assert not Path(with_validation[1]).exists()
    assert not list(output_dir.rglob("_validation_bundle_*.py"))


def test_generated_validation_bundle_builds_validation_dags(
    create_dag_files_mod, monkeypatch, tmp_path
):
    import bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser as parser_module
    import bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher as dispatcher_module

    dags_root = tmp_path / "dags"
    _write_validation_declaration(dags_root, "people", "dw_employee")
    _patch_bundle_deps(create_dag_files_mod, monkeypatch, dags_root)

    class FakeParser:
        def __init__(self, dag_name):
            self.dag_name = dag_name

        def dag_declaration(self):
            return {
                "dag": {"name": self.dag_name},
                "workflow": {"layer": "clean"},
                "cluster": {"type": "xs"},
                "validation": {"cluster": {"type": "xs"}},
            }

    captured = {}

    class FakeWorkflow:
        def __init__(self, dag_name):
            self.dag_name = dag_name

        def build_dag(self):
            return DAG(dag_id=f"bietlejuice.{self.dag_name}_validation")

    class FakeFactory:
        def __init__(self, dag_name):
            self.dag_name = dag_name

        def get_workflow(self):
            return FakeWorkflow(self.dag_name)

    class FakeDispatcher:
        def __init__(self, layer):
            self.layer = layer

        def get_factory(self, **kwargs):
            captured.update(kwargs)
            return FakeFactory(kwargs["dag_args"]["name"])

    monkeypatch.setattr(parser_module, "DAGYamlParser", FakeParser)
    monkeypatch.setattr(dispatcher_module, "FactoryDispatcher", FakeDispatcher)

    bundles = create_dag_files_mod.create_domain_bundles(
        output_dir=str(dags_root / "_astro_bundles"),
        exclude_file=str(tmp_path / "excludes.txt"),
        include_validation=True,
    )
    validation_bundle = _only_validation_bundle(bundles)
    dagbag = DagBag(
        dag_folder=validation_bundle, include_examples=False, safe_mode=False
    )

    assert not dagbag.import_errors, dagbag.import_errors
    assert set(dagbag.dags) == {"bietlejuice.dw_employee_validation"}
    assert captured["is_validation"] is True
    assert captured["dataset_dependencies"] is None
    assert captured["validation_config"] == {"cluster": {"type": "xs"}}


def test_validation_bundle_quarantines_missing_validation_block(
    create_dag_files_mod, monkeypatch, tmp_path
):
    """Guards against a stale bundle whose declaration lost validation.cluster."""
    import bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser as parser_module

    dags_root = tmp_path / "dags"
    _write_validation_declaration(dags_root, "people", "dw_employee")
    _patch_bundle_deps(create_dag_files_mod, monkeypatch, dags_root)

    class FakeParser:
        def __init__(self, dag_name):
            self.dag_name = dag_name

        def dag_declaration(self):
            return {
                "dag": {"name": self.dag_name},
                "workflow": {"layer": "clean"},
                "cluster": {"type": "xs"},
            }

    monkeypatch.setattr(parser_module, "DAGYamlParser", FakeParser)
    bundles = create_dag_files_mod.create_domain_bundles(
        output_dir=str(dags_root / "_astro_bundles"),
        exclude_file=str(tmp_path / "excludes.txt"),
        include_validation=True,
    )
    validation_bundle = _only_validation_bundle(bundles)
    dagbag = DagBag(
        dag_folder=validation_bundle, include_examples=False, safe_mode=False
    )

    assert not dagbag.import_errors, dagbag.import_errors
    quarantined = dagbag.dags["bietlejuice.dw_employee__validation"]
    assert "broken-dag" in quarantined.tags
    assert "validation.cluster" in quarantined.doc_md


def test_domain_bundle_template_supports_both_modes():
    template = (
        REPO_ROOT / "packages/bietlejuice-compiler/scripts/ci_cd/airflow_dag_builder/"
        "__domain_bundle_template__.py"
    ).read_text()
    assert "__IS_VALIDATION__" in template
    assert "merge_validation_cluster_args" in template
    assert "is_validation" in template


def _write_migration_dag(
    root: Path, kind: str, folder_suffix: str, dag_id: str, *, broken: bool = False
) -> Path:
    """Write a minimal standalone migration-style DAG under platform/."""
    folder = f"migration_{kind}_{folder_suffix}"
    dag_dir = root / "platform" / folder
    dag_dir.mkdir(parents=True, exist_ok=True)
    dag_file = dag_dir / f"{folder}_dag.py"
    if broken:
        dag_file.write_text("raise RuntimeError('boom')\n")
    else:
        dag_file.write_text(
            "from datetime import datetime\n"
            "from pathlib import Path\n"
            "from airflow import DAG\n"
            f"DAG_DIR = Path(__file__).resolve().parent\n"
            f"with DAG(dag_id={dag_id!r}, schedule=None, "
            "start_date=datetime(2026, 1, 1), catchup=False) as dag:\n"
            "    assert DAG_DIR.name == Path(__file__).resolve().parent.name\n"
        )
    return dag_file


def test_create_python_dag_bundles_chunks_by_kind(
    create_dag_files_mod, monkeypatch, tmp_path
):
    dags_root = tmp_path / "dags"
    _write_migration_dag(dags_root, "twin", "a", "migration_twin_a")
    _write_migration_dag(dags_root, "twin", "b", "migration_twin_b")
    _write_migration_dag(dags_root, "emr", "a", "migration_emr_a")
    _write_migration_dag(dags_root, "compare", "a", "migration_compare_a")
    # Unrelated platform DAG must be ignored.
    other = dags_root / "platform" / "astro"
    other.mkdir(parents=True)
    (other / "astro_dag.py").write_text("from airflow import DAG\n")

    monkeypatch.setattr(create_dag_files_mod, "DAG_PACKAGES_ROOT", str(dags_root))
    output_dir = dags_root / "_astro_bundles"
    bundles = create_dag_files_mod.create_python_dag_bundles(
        max_dags_per_bundle=1,
        output_dir=str(output_dir),
    )

    names = [Path(bundle).name for bundle in bundles]
    assert names == [
        "_twin_bundle_01.py",
        "_twin_bundle_02.py",
        "_emr_bundle_01.py",
        "_compare_bundle_01.py",
    ]
    twin_01 = Path(bundles[0]).read_text()
    assert "platform/migration_twin_a/migration_twin_a_dag.py" in twin_01
    assert "platform/migration_twin_b/migration_twin_b_dag.py" not in twin_01
    assert "platform/astro/" not in twin_01
    assert "astro_dag.py" not in twin_01


def test_create_python_dag_bundles_stable_ids_and_file_resolution(
    create_dag_files_mod, monkeypatch, tmp_path
):
    dags_root = tmp_path / "dags"
    _write_migration_dag(dags_root, "twin", "offer", "migration_twin_offer")
    _write_migration_dag(dags_root, "compare", "employee", "migration_compare_employee")

    monkeypatch.setattr(create_dag_files_mod, "DAG_PACKAGES_ROOT", str(dags_root))
    bundles = create_dag_files_mod.create_python_dag_bundles(
        output_dir=str(dags_root / "_astro_bundles"),
    )

    assert len(bundles) == 2  # one twin, one compare (emr empty → no file)
    dagbag = DagBag(
        dag_folder=str(dags_root / "_astro_bundles"), include_examples=False
    )

    assert not dagbag.import_errors, dagbag.import_errors
    assert set(dagbag.dags) == {
        "migration_twin_offer",
        "migration_compare_employee",
    }


def test_create_python_dag_bundles_quarantines_build_failures(
    create_dag_files_mod, monkeypatch, tmp_path
):
    dags_root = tmp_path / "dags"
    _write_migration_dag(
        dags_root, "twin", "broken_a", "migration_twin_broken_a", broken=True
    )
    _write_migration_dag(
        dags_root, "twin", "broken_b", "migration_twin_broken_b", broken=True
    )

    monkeypatch.setattr(create_dag_files_mod, "DAG_PACKAGES_ROOT", str(dags_root))
    bundles = create_dag_files_mod.create_python_dag_bundles(
        output_dir=str(dags_root / "_astro_bundles"),
    )
    assert len(bundles) == 1
    dagbag = DagBag(dag_folder=bundles[0], include_examples=False, safe_mode=False)

    assert not dagbag.import_errors, dagbag.import_errors
    assert set(dagbag.dags) == {
        "migration_twin_broken_a",
        "migration_twin_broken_b",
    }
    assert "broken-dag" in dagbag.dags["migration_twin_broken_a"].tags
    assert "broken-dag" in dagbag.dags["migration_twin_broken_b"].tags


def test_python_bundle_template_keeps_dagbag_safe_mode_tokens():
    template = (
        REPO_ROOT / "packages/bietlejuice-compiler/scripts/ci_cd/airflow_dag_builder/"
        "__python_bundle_template__.py"
    ).read_text()
    assert "airflow" in template
    assert "dag" in template.lower()
    assert "DAG" in template
