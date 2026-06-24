"""Discover cluster validation DAGs from bi-etl-ejuice and QuintoML Wonka configs."""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
DAGS_ROOT = REPO_ROOT / "dags"
COMPILER_ROOT = REPO_ROOT / "packages" / "bietlejuice-compiler"
CORE_SRC = REPO_ROOT / "packages" / "bietlejuice-core" / "src"
COMPILER_SCRIPTS = COMPILER_ROOT / "scripts"

for path in (COMPILER_ROOT, COMPILER_SCRIPTS, COMPILER_ROOT / "src", CORE_SRC):
    path_str = str(path)
    if path_str not in sys.path:
        sys.path.insert(0, path_str)

from ci_cd.airflow_dag_builder.wonka_config_paths import (  # noqa: E402
    DEFAULT_QUINTOML_ROOT,
    VALIDATION_DAG_SUFFIX,
    WONKA_DAG_ID_PREFIX,
    wonka_airflow_dag_id,
)

DAG_ID_PREFIX = "bietlejuice."
WONKA_LINE = "wonka"


@dataclass(frozen=True)
class ValidationDag:
    line: str
    dag_name: str
    dag_id: str
    cluster_path: Path

    @property
    def original_dag_id(self) -> str:
        """Prod Airflow DAG id (validation id without ``__validation`` suffix)."""
        suffix = VALIDATION_DAG_SUFFIX
        if self.dag_id.endswith(suffix):
            return self.dag_id[: -len(suffix)]
        return self.dag_id

    @property
    def cluster_path_display(self) -> str:
        try:
            return self.cluster_path.relative_to(REPO_ROOT).as_posix()
        except ValueError:
            try:
                return self.cluster_path.relative_to(DEFAULT_QUINTOML_ROOT).as_posix()
            except ValueError:
                return str(self.cluster_path)


def _airflow_dag_name_from_cluster_path(cluster_path: Path) -> str:
    """Resolve Airflow dag.name from sibling declaration (falls back to folder name)."""
    folder_name = cluster_path.name.replace("_cluster.yml", "")
    declaration_path = cluster_path.parent / f"{folder_name}_declaration.yml"
    if not declaration_path.is_file():
        return folder_name

    try:
        document = yaml.safe_load(declaration_path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError):
        return folder_name

    if not isinstance(document, dict):
        return folder_name

    dag_section = document.get("dag")
    if not isinstance(dag_section, dict):
        return folder_name

    declared_name = dag_section.get("name")
    if isinstance(declared_name, str) and declared_name.strip():
        return declared_name.strip()
    return folder_name


def _parse_bietlejuice_cluster_file(
    cluster_path: Path, dags_root: Path
) -> ValidationDag | None:
    try:
        document = yaml.safe_load(cluster_path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError):
        return None

    if not isinstance(document, dict):
        return None

    validation = document.get("validation")
    if not isinstance(validation, dict) or not validation.get("cluster"):
        return None

    try:
        relative = cluster_path.relative_to(dags_root)
    except ValueError:
        return None

    if len(relative.parts) < 2:
        return None

    dag_name = cluster_path.name.replace("_cluster.yml", "")
    airflow_dag_name = _airflow_dag_name_from_cluster_path(cluster_path)
    line = relative.parts[0]
    dag_id = f"{DAG_ID_PREFIX}{airflow_dag_name}{VALIDATION_DAG_SUFFIX}"
    return ValidationDag(
        line=line,
        dag_name=dag_name,
        dag_id=dag_id,
        cluster_path=cluster_path,
    )


def _parse_wonka_prod_yml(prod_yml_path: Path) -> ValidationDag | None:
    try:
        document = yaml.safe_load(prod_yml_path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError):
        return None

    if not isinstance(document, dict):
        return None

    validation = document.get("validation")
    if not isinstance(validation, dict) or not validation.get("cluster"):
        return None

    prod_dag_id = wonka_airflow_dag_id(document)
    if not prod_dag_id:
        return None

    feature_set = prod_dag_id.removeprefix(WONKA_DAG_ID_PREFIX)
    dag_name = prod_yml_path.parent.parent.name
    dag_id = f"{prod_dag_id}{VALIDATION_DAG_SUFFIX}"
    return ValidationDag(
        line=WONKA_LINE,
        dag_name=feature_set or dag_name,
        dag_id=dag_id,
        cluster_path=prod_yml_path,
    )


def discover_bietlejuice_validation_dags(
    dags_root: Path | None = None,
) -> list[ValidationDag]:
    root = dags_root or DAGS_ROOT
    discovered: list[ValidationDag] = []
    for cluster_path in sorted(root.rglob("*_cluster.yml")):
        item = _parse_bietlejuice_cluster_file(cluster_path, root)
        if item is not None:
            discovered.append(item)
    return discovered


def discover_wonka_validation_dags(
    quintoml_root: Path | None = None,
) -> list[ValidationDag]:
    root = quintoml_root or DEFAULT_QUINTOML_ROOT
    wonka_root = root / "jobs" / "wonka"
    if not wonka_root.is_dir():
        return []
    discovered: list[ValidationDag] = []
    for prod_yml in sorted(wonka_root.glob("*/configs/prod.yml")):
        item = _parse_wonka_prod_yml(prod_yml)
        if item is not None:
            discovered.append(item)
    return discovered


def discover_validation_dags(
    dags_root: Path | None = None,
    quintoml_root: Path | None = None,
) -> list[ValidationDag]:
    """Discover validation DAGs from bi-etl-ejuice and optional QuintoML Wonka configs."""
    combined = discover_bietlejuice_validation_dags(dags_root)
    if quintoml_root is not None:
        combined.extend(discover_wonka_validation_dags(quintoml_root))
    return combined


def _split_csv(value: str | None) -> set[str]:
    if not value:
        return set()
    return {part.strip() for part in value.split(",") if part.strip()}


def filter_validation_dags(
    dags: Sequence[ValidationDag],
    *,
    lines: str | None = None,
    exclude_lines: str | None = None,
    dag_names: str | None = None,
    exclude_dag_names: str | None = None,
    dag_ids: str | None = None,
) -> list[ValidationDag]:
    include_lines = _split_csv(lines)
    exclude_line_set = _split_csv(exclude_lines)
    include_dag_names = _split_csv(dag_names)
    exclude_dag_name_set = _split_csv(exclude_dag_names)
    include_dag_ids = _split_csv(dag_ids)

    has_include_filter = bool(include_lines or include_dag_names or include_dag_ids)

    filtered: list[ValidationDag] = []
    for item in dags:
        if has_include_filter:
            line_match = bool(include_lines) and item.line in include_lines
            dag_match = bool(include_dag_names) and item.dag_name in include_dag_names
            id_match = bool(include_dag_ids) and item.dag_id in include_dag_ids
            if not (line_match or dag_match or id_match):
                continue

        if item.line in exclude_line_set:
            continue
        if item.dag_name in exclude_dag_name_set:
            continue

        filtered.append(item)

    return filtered


def group_by_line(dags: Iterable[ValidationDag]) -> dict[str, list[ValidationDag]]:
    grouped: dict[str, list[ValidationDag]] = {}
    for item in sorted(dags, key=lambda d: (d.line, d.dag_name)):
        grouped.setdefault(item.line, []).append(item)
    return grouped
