"""Discover DAGs eligible for EMR migration (non-emr_* cluster presets)."""

from __future__ import annotations

from pathlib import Path
from typing import List, Tuple

import yaml

from paths import REPO_ROOT


def _cluster_type(cluster_yml: Path) -> str:
    with cluster_yml.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    cluster = data.get("cluster") or {}
    return str(cluster.get("type", ""))


def _validate_dag_path(domain: str, dag_name: str, repo_root: Path) -> None:
    dag_path = repo_root / "dags" / domain / dag_name
    if not dag_path.is_dir():
        raise FileNotFoundError(f"DAG not found: {dag_path}")


def parse_scope_pairs(
    spec: str,
    *,
    repo_root: Path | None = None,
) -> List[Tuple[str, str]]:
    """Parse comma-separated domain/dag pairs, e.g. agents/enrich_agent,fintech/enrich_billing."""
    root = repo_root or REPO_ROOT
    pairs: List[Tuple[str, str]] = []
    for entry in spec.split(","):
        item = entry.strip()
        if not item:
            continue
        if "/" not in item:
            raise ValueError(f"Invalid scope entry (expected domain/dag): {item}")
        domain, dag_name = item.split("/", 1)
        domain = domain.strip()
        dag_name = dag_name.strip()
        if not domain or not dag_name:
            raise ValueError(f"Invalid scope entry (expected domain/dag): {item}")
        _validate_dag_path(domain, dag_name, root)
        pairs.append((domain, dag_name))
    if not pairs:
        raise ValueError("Scope string is empty")
    return pairs


def load_scope_file(
    path: Path,
    *,
    repo_root: Path | None = None,
) -> List[Tuple[str, str]]:
    """Load domain/dag pairs from a YAML list file."""
    root = repo_root or REPO_ROOT
    with path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if not isinstance(data, list) or not data:
        raise ValueError(f"Scope file must be a non-empty YAML list: {path}")

    pairs: List[Tuple[str, str]] = []
    for index, item in enumerate(data, start=1):
        if not isinstance(item, dict):
            raise ValueError(f"Scope entry {index} must be a mapping with domain and dag")
        domain = str(item.get("domain", "")).strip()
        dag_name = str(item.get("dag", "")).strip()
        if not domain or not dag_name:
            raise ValueError(f"Scope entry {index} must include domain and dag")
        _validate_dag_path(domain, dag_name, root)
        pairs.append((domain, dag_name))
    return pairs


def discover_dags_for_line(
    line: str,
    repo_root: Path | None = None,
) -> List[Tuple[str, str]]:
    """Return (domain, dag_name) pairs not yet on emr_* cluster presets."""
    root = repo_root or REPO_ROOT
    line_path = root / "dags" / line
    if not line_path.is_dir():
        raise FileNotFoundError(f"Line path not found: {line_path}")

    dags: List[Tuple[str, str]] = []
    for dag_dir in sorted(line_path.iterdir()):
        if not dag_dir.is_dir():
            continue
        cluster_files = list(dag_dir.glob("*_cluster.yml"))
        if not cluster_files:
            continue
        cluster_type = _cluster_type(cluster_files[0])
        if cluster_type.startswith("emr_"):
            continue
        queries = dag_dir / "queries"
        if not queries.is_dir():
            continue
        dags.append((line, dag_dir.name))
    return dags


def discover_dags_by_names(
    domain: str,
    dag_names: List[str],
    repo_root: Path | None = None,
) -> List[Tuple[str, str]]:
    root = repo_root or REPO_ROOT
    found: List[Tuple[str, str]] = []
    for dag_name in dag_names:
        _validate_dag_path(domain, dag_name, root)
        found.append((domain, dag_name))
    return found
