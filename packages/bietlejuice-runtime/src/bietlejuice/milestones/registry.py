"""Load and validate milestone registry from table metadata (or dict)."""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence, Tuple

import yaml

from bietlejuice.milestones.contract import MilestoneTableSpec

REQUIRED_TYPE_KEYS = ("milestone_type", "scan")
REQUIRED_SCAN_KEYS = ("ts_column", "lookback_days")


def _normalize_milestones_block(raw: Dict[str, Any]) -> Tuple[Tuple[str, ...], Dict[str, Dict[str, Any]]]:
    """Accept either nested ``types:`` or a flat map of milestone entries.

    Flat map form (legacy-friendly): every non-reserved top-level key is a type.
    Reserved: ``sticky_columns``, ``types``.
    """
    sticky = tuple(str(c) for c in (raw.get("sticky_columns") or ()))
    if "types" in raw:
        types = raw["types"]
        if not isinstance(types, dict):
            raise ValueError("m=normalize, msg=milestones.types must be a mapping")
        return sticky, types

    types = {
        key: value
        for key, value in raw.items()
        if key not in {"sticky_columns", "types"} and isinstance(value, dict)
    }
    if not types:
        raise ValueError("m=normalize, msg=milestones has no type entries")
    return sticky, types


def validate_milestones_registry(raw: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    """Validate milestones block; return types map keyed by entry name."""
    if not isinstance(raw, dict):
        raise ValueError("m=validate_milestones_registry, msg=milestones must be a mapping")

    _, types = _normalize_milestones_block(raw)
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
        strategy = defn.get("strategy", "sql")
        if strategy != "sql":
            raise ValueError(
                f"m=validate_milestones_registry, milestone={name}, "
                f"msg=Invalid strategy={strategy!r}; only sql is supported"
            )
        sql_file = defn.get("sql_file") or defn.get("sql_path")
        if not sql_file:
            raise ValueError(
                f"m=validate_milestones_registry, milestone={name}, "
                "msg=sql_file (or sql_path) is required"
            )
        entry = dict(defn)
        entry["strategy"] = "sql"
        entry["sql_file"] = str(sql_file)
        validated[name] = entry
    return validated


def sticky_columns_from_registry(raw: Dict[str, Any]) -> Tuple[str, ...]:
    sticky, _ = _normalize_milestones_block(raw)
    return sticky


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


def load_milestones_from_metadata_yaml(content: str) -> Tuple[Dict[str, Dict[str, Any]], Tuple[str, ...]]:
    parsed = yaml.safe_load(content) or {}
    if not isinstance(parsed, dict):
        raise ValueError("m=load_milestones_from_metadata_yaml, msg=YAML root must be a mapping")
    return parse_milestones_metadata_document(parsed)


def build_table_spec(
    merge_on: Sequence[str],
    sticky_columns: Optional[Sequence[str]] = None,
) -> MilestoneTableSpec:
    return MilestoneTableSpec.from_merge_on(merge_on, sticky_columns=sticky_columns)
