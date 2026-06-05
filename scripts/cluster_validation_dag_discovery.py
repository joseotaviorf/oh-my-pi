"""Discover cluster validation DAGs from repo *_cluster.yml files."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
DAGS_ROOT = REPO_ROOT / "dags"
DAG_ID_PREFIX = "bietlejuice."
VALIDATION_DAG_SUFFIX = "__validation"


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


def _parse_cluster_file(cluster_path: Path, dags_root: Path) -> ValidationDag | None:
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


def discover_validation_dags(dags_root: Path | None = None) -> list[ValidationDag]:
    root = dags_root or DAGS_ROOT
    discovered: list[ValidationDag] = []
    for cluster_path in sorted(root.rglob("*_cluster.yml")):
        item = _parse_cluster_file(cluster_path, root)
        if item is not None:
            discovered.append(item)
    return discovered


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
