import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[6]))

from scripts.ci_cd.source_layer_validation.dag_source_paths import (  # noqa: E402
    dag_has_new_declaration,
    dag_requires_strict_validation,
    is_source_artifact_rel_path,
    list_added_metadata_files,
    list_added_source_artifacts,
)


def test_is_source_artifact():
    assert is_source_artifact_rel_path("queries/clean/x.sql") is True
    assert is_source_artifact_rel_path("spark_jobs/prod_conf.yml") is True
    assert is_source_artifact_rel_path("spark_jobs/load_x.py") is True
    assert is_source_artifact_rel_path("metadata/dw/x.yml") is False
    assert is_source_artifact_rel_path("my_dag_declaration.yml") is False


def test_list_added_source_artifacts():
    dag = "dags/domain/my_dag"
    changed = {
        "dags/domain/my_dag/queries/clean/a.sql": "A",
        "dags/domain/my_dag/metadata/x.yml": "A",
        "dags/domain/my_dag/queries/clean/old.sql": "M",
    }
    got = list_added_source_artifacts(dag, changed)
    assert got == ["dags/domain/my_dag/queries/clean/a.sql"]


def test_list_added_metadata_files():
    dag = "dags/domain/my_dag"
    changed = {
        "dags/domain/my_dag/metadata/clean/x.yml": "A",
        "dags/domain/my_dag/metadata/clean/old.yml": "M",
        "dags/domain/my_dag/queries/clean/a.sql": "A",
    }
    got = list_added_metadata_files(dag, changed)
    assert got == ["dags/domain/my_dag/metadata/clean/x.yml"]


def test_new_declaration_triggers_strict():
    dag = "dags/domain/new_one"
    decl = "dags/domain/new_one/new_one_declaration.yml"
    assert dag_has_new_declaration(dag, {decl: "A"}) is True
    assert dag_has_new_declaration(dag, {decl: "M"}) is False


def test_dag_requires_strict():
    dag = "dags/domain/x"
    assert (
        dag_requires_strict_validation(
            dag,
            {"dags/domain/x/x_declaration.yml": "A"},
        )
        is True
    )
    assert (
        dag_requires_strict_validation(
            dag,
            {"dags/domain/x/queries/clean/f.sql": "A"},
        )
        is True
    )
    assert (
        dag_requires_strict_validation(
            dag,
            {"dags/domain/x/queries/clean/f.sql": "M"},
        )
        is False
    )
    assert (
        dag_requires_strict_validation(
            dag,
            {"dags/domain/x/metadata/a.yml": "A"},
        )
        is False
    )
