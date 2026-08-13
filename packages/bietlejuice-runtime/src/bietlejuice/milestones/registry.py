"""Load and validate milestone registry from table metadata (or dict)."""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple

import yaml

REQUIRED_TYPE_KEYS = ("milestone_type", "sql_file", "scan")
REQUIRED_SCAN_KEYS = ("ts_column", "lookback_days")


def validate_milestones_registry(raw: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    """Validate milestones block; return types map keyed by entry name.

    Expected shape::

        sticky_columns: [...]
        types:
          first_vb:
            milestone_type: first_vb
            sql_file: visit_events.sql
            scan: {ts_column: ..., lookback_days: N}
            params: {...}   # optional
    """
    if not isinstance(raw, dict):
        raise ValueError(
            "m=validate_milestones_registry, msg=milestones must be a mapping"
        )
    types = raw.get("types")
    if not isinstance(types, dict) or not types:
        raise ValueError(
            "m=validate_milestones_registry, msg=milestones.types must be a non-empty mapping"
        )

    validated: Dict[str, Dict[str, Any]] = {}
    for name, defn in types.items():
        if not isinstance(defn, dict):
            raise ValueError(
                f"m=validate_milestones_registry, milestone={name}, "
                "msg=entry must be a mapping"
            )
        missing = [key for key in REQUIRED_TYPE_KEYS if key not in defn]
        if missing:
            raise ValueError(
                f"m=validate_milestones_registry, milestone={name}, "
                f"msg=Missing required keys: {missing}"
            )
        scan = defn["scan"]
        if not isinstance(scan, dict):
            raise ValueError(
                f"m=validate_milestones_registry, milestone={name}, "
                "msg=scan must be a mapping"
            )
        missing_scan = [key for key in REQUIRED_SCAN_KEYS if key not in scan]
        if missing_scan:
            raise ValueError(
                f"m=validate_milestones_registry, milestone={name}, "
                f"msg=Missing scan keys: {missing_scan}"
            )
        entry = dict(defn)
        entry["sql_file"] = str(defn["sql_file"])
        validated[name] = entry
    return validated


def sticky_columns_from_registry(raw: Dict[str, Any]) -> Tuple[str, ...]:
    return tuple(str(c) for c in (raw.get("sticky_columns") or ()))


def resolve_milestones_for_run(
    registry: Dict[str, Dict[str, Any]],
    milestones_to_run: Optional[List[str]] = None,
    bootstrap_milestones: Optional[List[str]] = None,
) -> Dict[str, Dict[str, Any]]:
    """Subset registry and inject per-run ``bootstrap`` from DAG conf."""
    if milestones_to_run:
        missing = [name for name in milestones_to_run if name not in registry]
        if missing:
            raise ValueError(
                "m=resolve_milestones_for_run, "
                f"msg=Unknown milestones_to_run entries: {missing}"
            )
        selected_names = list(milestones_to_run)
    else:
        selected_names = list(registry.keys())

    bootstrap_set = set(bootstrap_milestones or [])
    unknown_bootstrap = sorted(bootstrap_set - set(registry.keys()))
    if unknown_bootstrap:
        raise ValueError(
            "m=resolve_milestones_for_run, "
            f"msg=Unknown bootstrap_milestones entries: {unknown_bootstrap}"
        )

    resolved: Dict[str, Dict[str, Any]] = {}
    for name in selected_names:
        defn = dict(registry[name])
        defn["bootstrap"] = name in bootstrap_set
        resolved[name] = defn
    return resolved


def parse_milestones_metadata_document(
    document: Dict[str, Any],
) -> Tuple[Dict[str, Dict[str, Any]], Tuple[str, ...]]:
    """Extract validated types + sticky columns from a metadata YAML document."""
    block = document.get("milestones")
    if block is None:
        raise ValueError(
            "m=parse_milestones_metadata_document, msg=Missing milestones section"
        )
    sticky = sticky_columns_from_registry(block)
    return validate_milestones_registry(block), sticky


def load_milestones_from_metadata_yaml(
    content: str,
) -> Tuple[Dict[str, Dict[str, Any]], Tuple[str, ...]]:
    parsed = yaml.safe_load(content) or {}
    if not isinstance(parsed, dict):
        raise ValueError(
            "m=load_milestones_from_metadata_yaml, msg=YAML root must be a mapping"
        )
    return parse_milestones_metadata_document(parsed)
