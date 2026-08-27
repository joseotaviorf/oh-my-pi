"""
Extract metastore table references from Qube DAG declaration YAML specs.

Used by source-layer policy validation and dependency generation. Mirrors the
runtime ``source_resolver`` contract without requiring Spark ``Config``.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, Iterable, Mapping, Optional, Set, Tuple

import yaml

QUBE_WORKFLOW_TYPES = frozenset({"qube_dimension", "qube_measure", "qube_metric"})

TABLE_FQN_PATTERN = re.compile(r"^[a-zA-Z][a-zA-Z0-9_]*\.[a-zA-Z][a-zA-Z0-9_]*$")


def parse_table_fqn(value: object) -> Optional[Tuple[str, str]]:
    """Return (schema, table) if value looks like schema.table, else None."""
    if not isinstance(value, str):
        return None
    value = value.strip().strip('"').strip("'")
    if not TABLE_FQN_PATTERN.match(value):
        return None
    schema, table = value.split(".", 1)
    return schema, table


def declaration_path_for_dag_root(dag_root: Path) -> Path:
    """``dags/<domain>/<name>`` -> ``.../<name>/<name>_declaration.yml``."""
    name = dag_root.name
    return dag_root / f"{name}_declaration.yml"


def load_declaration_dict(dag_root: Path) -> Optional[Dict[str, Any]]:
    """Load declaration YAML as dict, or None if missing/unreadable."""
    path = declaration_path_for_dag_root(dag_root)
    if not path.is_file():
        return None
    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except (OSError, yaml.YAMLError):
        return None
    if not isinstance(data, dict):
        return None
    return data


def _default_core_table(entity: str) -> str:
    return f"core_{entity}.{entity}"


def extract_table_fqns_from_qube_source(
    source: Mapping[str, Any], entity: str, include_all_entities: bool = False
) -> Set[str]:
    """
    Resolve source + universe table FQNs from a qube_specs ``source`` block.

    Returns schema.table strings suitable for layer policy checks and DAG
    dependency inference. Raw-layer references are included (validation rejects
    them via ``layer_policy_matrix`` / runtime ``SourceLayerError``).

    ``include_all_entities`` is a top-level ``qube_specs`` field (see the runtime
    ``DimensionSpec`` / ``build_dimension``), NOT a ``source`` sub-field, so the
    caller must read it from the spec level and pass it in. When it is true and no
    explicit ``universe_table`` is set, the default ``core_{entity}.{entity}``
    universe is added as a dependency.
    """
    tables: Set[str] = set()

    schema = source.get("source_schema")
    table_name = source.get("table_name")
    if schema and table_name:
        tables.add(f"{schema}.{table_name}")
    elif source.get("table"):
        tables.add(str(source["table"]))

    if not tables:
        tables.add(_default_core_table(entity))

    universe_table = source.get("universe_table")
    if universe_table:
        tables.add(str(universe_table))
    elif include_all_entities:
        tables.add(_default_core_table(entity))

    return {t for t in tables if parse_table_fqn(t)}


def extract_table_fqns_from_qube_specs(qube_specs: Mapping[str, Any]) -> Set[str]:
    """Extract all referenced tables from a workflow.qube_specs dict."""
    if not qube_specs:
        return set()

    entity = str(qube_specs.get("entity", "")).strip()
    if not entity:
        return set()

    # include_all_entities lives at the qube_specs level (sibling of source/logic),
    # matching the runtime DimensionSpec contract.
    include_all_entities = bool(qube_specs.get("include_all_entities"))

    tables: Set[str] = set()
    source = qube_specs.get("source")
    if isinstance(source, dict):
        tables |= extract_table_fqns_from_qube_source(
            source, entity, include_all_entities
        )

    return tables


def extract_tables_from_qube_declaration(
    declaration: Mapping[str, Any],
) -> Set[str]:
    """Extract source tables from a loaded DAG declaration dict."""
    workflow = declaration.get("workflow")
    if not isinstance(workflow, dict):
        return set()

    wtype = (workflow.get("type") or "").strip().lower()
    if wtype not in QUBE_WORKFLOW_TYPES:
        return set()

    qube_specs = workflow.get("qube_specs")
    if not isinstance(qube_specs, dict):
        return set()

    return extract_table_fqns_from_qube_specs(qube_specs)


def extract_tables_from_qube_declaration_path(decl_path: Path) -> Set[str]:
    """Load a declaration YAML and extract Qube source table FQNs."""
    try:
        with open(decl_path, encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except (OSError, yaml.YAMLError):
        return set()
    if not isinstance(data, dict):
        return set()
    return extract_tables_from_qube_declaration(data)


def extract_tables_from_qube_dag_root(dag_root: Path) -> Tuple[Optional[str], Set[str]]:
    """
    Return (declaration path, tables) for a Qube DAG folder.

    Path is None when the folder has no readable declaration.
    """
    decl_path = declaration_path_for_dag_root(dag_root)
    if not decl_path.is_file():
        return None, set()

    tables = extract_tables_from_qube_declaration_path(decl_path)
    return str(decl_path), tables


def iter_qube_dag_roots(dags_root: Path) -> Iterable[Path]:
    """Yield ``dags/qube/<folder>/`` paths that contain a declaration file."""
    qube_dir = dags_root / "qube"
    if not qube_dir.is_dir():
        return

    for subdir in sorted(qube_dir.iterdir()):
        if not subdir.is_dir():
            continue
        decl = declaration_path_for_dag_root(subdir)
        if decl.is_file():
            yield subdir


def dag_id_from_declaration(declaration: Mapping[str, Any]) -> Optional[str]:
    """Return ``bietlejuice.<dag.name>`` from a declaration, if present."""
    dag = declaration.get("dag")
    if not isinstance(dag, dict):
        return None
    name = dag.get("name")
    if not isinstance(name, str) or not name.strip():
        return None
    return f"bietlejuice.{name.strip()}"


def qube_table_dependencies_from_dags_root(dags_root: Path) -> Dict[str, Set[str]]:
    """
    Map Qube DAG ids to upstream source table FQNs for dependency generation.

    Only dimension and measure DAGs declare external sources; metric DAGs read
    from qube_dimensions / qube_measures (handled by metric workflow tasks).
    """
    out: Dict[str, Set[str]] = {}
    for dag_root in iter_qube_dag_roots(dags_root):
        decl = load_declaration_dict(dag_root)
        if not decl:
            continue

        workflow = decl.get("workflow") or {}
        wtype = (workflow.get("type") or "").strip().lower()
        if wtype not in {"qube_dimension", "qube_measure"}:
            continue

        dag_id = dag_id_from_declaration(decl)
        if not dag_id:
            continue

        tables = extract_tables_from_qube_declaration(decl)
        if tables:
            out[dag_id] = tables

    return out
