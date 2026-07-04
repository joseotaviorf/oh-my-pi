"""Unit tests for QuintoML Wonka config path resolution."""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
COMPILER_ROOT = REPO_ROOT / "packages" / "bietlejuice-compiler"
CORE_SRC = REPO_ROOT / "packages" / "bietlejuice-core" / "src"
for path in (COMPILER_ROOT, COMPILER_ROOT / "src", CORE_SRC):
    sys.path.insert(0, str(path))

from scripts.ci_cd.airflow_dag_builder.rightsizing_validation_config import (  # noqa: E402
    dag_id_to_config_path,
)
from scripts.ci_cd.airflow_dag_builder.wonka_config_paths import (  # noqa: E402
    dag_id_to_wonka_prod_path,
    snake_to_wonka_job_dir,
    wonka_airflow_dag_id,
    wonka_feature_set_snake_from_dag_id,
)


def test_snake_to_kebab_dir():
    assert snake_to_wonka_job_dir("house_main") == "house-main"


def test_wonka_prod_path_from_dag_id(tmp_path: Path):
    quintoml_root = tmp_path
    expected = quintoml_root / "jobs" / "wonka" / "house-main" / "configs" / "prod.yml"
    assert (
        dag_id_to_wonka_prod_path("quintoml.wonka.house_main", quintoml_root) == expected
    )
    assert (
        dag_id_to_wonka_prod_path(
            "quintoml.wonka.house_main__validation", quintoml_root
        )
        == expected
    )


def test_feature_set_from_validation_dag_id():
    assert (
        wonka_feature_set_snake_from_dag_id("quintoml.wonka.user_visits__validation")
        == "user_visits"
    )


def test_dag_id_to_config_path_bietlejuice():
    repo_dags = REPO_ROOT / "dags"
    path = dag_id_to_config_path(
        "bietlejuice.enrich_ebdb_listing",
        dags_root=repo_dags,
        quintoml_root=REPO_ROOT,
    )
    if path is not None:
        assert path.name.endswith("_cluster.yml")


def test_dag_id_to_config_path_wonka(tmp_path: Path):
    quintoml_root = tmp_path
    path = dag_id_to_config_path(
        "quintoml.wonka.house_main",
        dags_root=REPO_ROOT / "dags",
        quintoml_root=quintoml_root,
    )
    assert path == quintoml_root / "jobs" / "wonka" / "house-main" / "configs" / "prod.yml"


def test_wonka_airflow_dag_id_prefers_dag_name_over_wonka_config_name():
    declaration = {
        "dag": {"name": "house_user_for_rent_events"},
        "workflow": {"wonka_config": {"name": "for_rent_events"}},
    }
    assert (
        wonka_airflow_dag_id(declaration)
        == "quintoml.wonka.house_user_for_rent_events"
    )


def test_wonka_airflow_dag_id_falls_back_to_wonka_config_name():
    assert (
        wonka_airflow_dag_id({"workflow": {"wonka_config": {"name": "house_main"}}})
        == "quintoml.wonka.house_main"
    )
    assert (
        wonka_airflow_dag_id(
            {
                "dag": {"name": "   "},
                "workflow": {"wonka_config": {"name": "house_main"}},
            }
        )
        == "quintoml.wonka.house_main"
    )


def test_wonka_airflow_dag_id_none_when_no_usable_name():
    assert wonka_airflow_dag_id({}) is None
    assert wonka_airflow_dag_id({"dag": None, "workflow": None}) is None
    assert (
        wonka_airflow_dag_id(
            {"dag": {"name": ""}, "workflow": {"wonka_config": {"name": "   "}}}
        )
        is None
    )
    assert (
        wonka_airflow_dag_id(
            {"dag": {"name": 123}, "workflow": {"wonka_config": {"name": None}}}
        )
        is None
    )


def test_wonka_airflow_dag_id_normalizes_hyphens_to_underscores():
    assert (
        wonka_airflow_dag_id({"dag": {"name": "house-user-for-rent-events"}})
        == "quintoml.wonka.house_user_for_rent_events"
    )
    assert (
        wonka_airflow_dag_id(
            {"workflow": {"wonka_config": {"name": "for-rent-events"}}}
        )
        == "quintoml.wonka.for_rent_events"
    )
