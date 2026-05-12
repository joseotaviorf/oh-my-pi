"""Resolve ``event_name`` for core history / current-state event configs."""

from copy import deepcopy
from typing import Any, Dict, List, Optional


def resolve_event_name(
    event_config: Dict[str, Any], index: Optional[int] = None
) -> str:
    """Return ``event_name`` from config, or ``ev_{target_col}`` if omitted.

    Explicit non-empty ``event_name`` always wins so existing enums stay stable.

    Args:
        event_config: One entry from ``event_configs`` YAML.
        index: Optional index for error messages.

    Raises:
        ValueError: If neither a usable ``event_name`` nor ``target_col`` is set.
    """
    raw_name = event_config.get("event_name")
    if raw_name is not None and str(raw_name).strip() != "":
        return str(raw_name).strip()

    target_col = event_config.get("target_col")
    if target_col is not None and str(target_col).strip() != "":
        return f"ev_{str(target_col).strip()}"

    suffix = f" at index {index}" if index is not None else ""
    raise ValueError(
        f"event_configs{suffix} must include non-empty 'event_name' or 'target_col'"
    )


def with_resolved_event_name(
    event_config: Dict[str, Any], index: Optional[int] = None
) -> Dict[str, Any]:
    """Deep copy of ``event_config`` with ``event_name`` set to the resolved value."""
    out = deepcopy(event_config)
    out["event_name"] = resolve_event_name(event_config, index=index)
    return out


def resolve_event_configs(event_configs: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Return new list of configs with each ``event_name`` resolved."""
    return [with_resolved_event_name(ec, index=i) for i, ec in enumerate(event_configs)]
