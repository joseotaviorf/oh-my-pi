# -*- coding: utf-8 -*-
"""Read workflow.layer and workflow.type from a DAG declaration YAML."""

from pathlib import Path
from typing import Any, Dict, Optional, Tuple

import yaml


def declaration_path_for_dag_root(dag_root: Path) -> Path:
    """``dags/<domain>/<name>`` -> ``.../<name>/<name>_declaration.yml``."""
    name = dag_root.name
    return dag_root / "{}_declaration.yml".format(name)


def load_declaration_dict(dag_root: Path) -> Optional[Dict[str, Any]]:
    """Load declaration YAML as dict, or None if missing/unreadable."""
    path = declaration_path_for_dag_root(dag_root)
    if not path.is_file():
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except (OSError, yaml.YAMLError):
        return None
    if not isinstance(data, dict):
        return None
    return data


def get_workflow_layer_and_type(dag_root: Path) -> Tuple[Optional[str], Optional[str]]:
    """
    Return (layer, type) lowercased strings from ``workflow.layer`` / ``workflow.type``.
    Missing keys -> None.
    """
    data = load_declaration_dict(dag_root)
    if not data:
        return None, None
    workflow = data.get("workflow")
    if not isinstance(workflow, dict):
        return None, None
    layer = workflow.get("layer")
    wtype = workflow.get("type")
    out_layer = layer.strip().lower() if isinstance(layer, str) else None
    out_type = wtype.strip().lower() if isinstance(wtype, str) else None
    return out_layer, out_type
