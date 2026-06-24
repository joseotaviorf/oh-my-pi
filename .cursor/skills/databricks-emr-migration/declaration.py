"""DAG declaration helpers for ORDER BY column resolution."""

from __future__ import annotations

from pathlib import Path
from typing import List, Optional

import yaml

from input_validation import format_order_by_clause as _format_order_by_clause, validate_order_by_column
from models import SchemaEntry


def load_declaration(domain: str, dag_name: str, repo_root: Optional[Path] = None) -> dict:
    root = repo_root or Path.cwd()
    decl_path = root / "dags" / domain / dag_name / f"{dag_name}_declaration.yml"
    if not decl_path.exists():
        return {}
    with decl_path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def get_z_order_by(domain: str, dag_name: str, table_name: str, repo_root: Optional[Path] = None) -> List[str]:
    declaration = load_declaration(domain, dag_name, repo_root)
    tables_customization = (
        declaration.get("workflow", {}).get("tables_customization", {}) or {}
    )
    table_cfg = tables_customization.get(table_name, {}) or {}
    z_order = table_cfg.get("z_order_by") or []
    return [str(col) for col in z_order]


def resolve_order_by_cols(
    table_name: str,
    schema: List[SchemaEntry],
    domain: str,
    dag_name: str,
    repo_root: Optional[Path] = None,
) -> List[str]:
    z_order = get_z_order_by(domain, dag_name, table_name, repo_root)
    if z_order:
        return [validate_order_by_column(str(col)) for col in z_order]

    col_names = [name for name, _type in schema]
    sk_cols = [name for name in col_names if name.startswith("sk_")]
    if sk_cols:
        return sk_cols[:3]

    id_cols = [name for name in col_names if name.startswith("id_")]
    if id_cols:
        return id_cols[:3]

    if not col_names:
        return ["1"]
    return [str(position) for position in range(1, min(len(col_names), 3) + 1)]


def format_order_by_clause(order_by_cols: List[str]) -> str:
    return _format_order_by_clause(order_by_cols)


def is_cdc_clean_workflow(
    domain: str,
    dag_name: str,
    layer: str,
    repo_root: Optional[Path] = None,
) -> bool:
    if layer != "clean":
        return False
    declaration = load_declaration(domain, dag_name, repo_root)
    return declaration.get("workflow", {}).get("type") == "cdc"
