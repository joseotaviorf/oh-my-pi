"""Path and naming helpers for QuintoML Wonka feature-set configs."""

from __future__ import annotations

import os
from pathlib import Path

WONKA_DAG_ID_PREFIX = "quintoml.wonka."
VALIDATION_DAG_SUFFIX = "__validation"
DEFAULT_QUINTOML_ROOT = Path(os.path.expanduser("~/Work/quintoml"))


def snake_to_wonka_job_dir(feature_set_snake: str) -> str:
    """Map Airflow feature-set snake name to QuintoML jobs/wonka kebab directory."""
    return feature_set_snake.replace("_", "-")


def wonka_feature_set_snake_from_dag_id(dag_id: str) -> str | None:
    """Return feature-set snake name from prod or validation Airflow dag id."""
    if dag_id.endswith(VALIDATION_DAG_SUFFIX):
        dag_id = dag_id[: -len(VALIDATION_DAG_SUFFIX)]
    if not dag_id.startswith(WONKA_DAG_ID_PREFIX):
        return None
    snake = dag_id.removeprefix(WONKA_DAG_ID_PREFIX)
    return snake or None


def wonka_airflow_dag_id(declaration: dict) -> str | None:
    """Resolve canonical prod Airflow dag id from a Wonka prod.yml document.

    The deployed dag id derives from ``dag.name`` (WonkaWorkflow builds
    ``quintoml.wonka.{dag_args['name']}``), NOT from the feature-set name:
    e.g. house-user-for-rent-events has wonka_config.name=for_rent_events but
    deploys as quintoml.wonka.house_user_for_rent_events. Fall back to
    ``workflow.wonka_config.name`` only when ``dag.name`` is absent.
    """
    dag_section = declaration.get("dag") or {}
    name = dag_section.get("name")
    if not isinstance(name, str) or not name.strip():
        workflow = declaration.get("workflow") or {}
        wonka_config = workflow.get("wonka_config") or {}
        name = wonka_config.get("name")
    if not isinstance(name, str) or not name.strip():
        return None
    return f"{WONKA_DAG_ID_PREFIX}{name.strip().replace('-', '_')}"


def wonka_prod_yml_path(
    feature_set_snake: str,
    quintoml_root: Path = DEFAULT_QUINTOML_ROOT,
) -> Path:
    job_dir = snake_to_wonka_job_dir(feature_set_snake)
    return quintoml_root / "jobs" / "wonka" / job_dir / "configs" / "prod.yml"


def dag_id_to_wonka_prod_path(
    dag_id: str,
    quintoml_root: Path = DEFAULT_QUINTOML_ROOT,
) -> Path | None:
    feature_set = wonka_feature_set_snake_from_dag_id(dag_id)
    if feature_set is None:
        return None
    return wonka_prod_yml_path(feature_set, quintoml_root)


def iter_wonka_prod_configs(quintoml_root: Path = DEFAULT_QUINTOML_ROOT) -> list[Path]:
    """All jobs/wonka/*/configs/prod.yml paths under quintoml_root."""
    wonka_root = quintoml_root / "jobs" / "wonka"
    if not wonka_root.is_dir():
        return []
    return sorted(wonka_root.glob("*/configs/prod.yml"))
