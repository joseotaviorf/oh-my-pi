"""Shared helpers: EMR instance groups -> instance fleets conversion."""

from __future__ import annotations

import copy
import re
from typing import List, Optional, Tuple

_FLEET_SPOT_DEFAULTS = {
    "allocation_strategy": "price-capacity-optimized",
    "bid_price_percentage": 100,
}


def is_emr_cluster_type(cluster_type: str) -> bool:
    return str(cluster_type).startswith("emr_")


def instance_family_fallbacks(node_type_id: str) -> List[str]:
    value = str(node_type_id).strip()
    match = re.match(r"^([mrc])(\d+g)\.(.+)$", value)
    if not match:
        return [value]
    family, _gen, size = match.group(1), match.group(2), match.group(3)
    if family == "m":
        return [f"m6g.{size}", f"m7g.{size}"]
    if family == "r":
        return [f"r6g.{size}", f"r7g.{size}", f"r6i.{size}"]
    if family == "c":
        return [f"c6g.{size}", f"c7g.{size}"]
    return [value]


def _resolve_node_type_from_block(
    block: dict, fallback: str, legacy_flat: Optional[str] = None
) -> str:
    if isinstance(block, dict):
        node_type = block.get("node_type_id")
        if node_type:
            return str(node_type)
        instance_types = block.get("instance_types") or []
        if instance_types:
            return str(instance_types[0])
    if legacy_flat:
        return str(legacy_flat)
    return fallback


def _block_worker_count(block: dict) -> int:
    if not isinstance(block, dict) or not block:
        return 0
    if "instance_count" in block:
        return int(block.get("instance_count", 0) or 0)
    return int(block.get("target_on_demand", 0) or 0) + int(
        block.get("target_spot", 0) or 0
    )


def extract_group_topology(effective: dict) -> Tuple[str, int, int, str, str]:
    master = str(
        effective.get("master_node_type_id")
        or effective.get("driver_node_type_id")
        or "m6g.xlarge"
    )
    core_block = effective.get("core_nodes") or {}
    task_block = effective.get("task_nodes") or {}
    legacy_type = effective.get("node_type_id")
    legacy_workers = effective.get("num_workers")
    legacy_task = effective.get("num_task_workers")

    core_type = _resolve_node_type_from_block(core_block, master, legacy_type)
    task_type = _resolve_node_type_from_block(
        task_block, core_type, effective.get("task_node_type_id")
    )

    core_count = _block_worker_count(core_block)
    task_count = _block_worker_count(task_block)

    if core_count == 0 and task_count == 0:
        if legacy_workers is not None and legacy_task is not None:
            core_count = max(int(legacy_workers) - int(legacy_task), 0)
            task_count = int(legacy_task)
        elif legacy_workers is not None:
            core_count = int(legacy_workers)

    return master, core_count, task_count, core_type, task_type


def task_uses_spot(effective: dict) -> bool:
    aws = effective.get("aws_attributes") or {}
    task_availability = aws.get("task_availability")
    if task_availability:
        return str(task_availability).upper() == "SPOT"
    return str(aws.get("availability", "SPOT")).upper() != "ON_DEMAND"


def build_core_fleet_block(core_count: int, node_type_id: str):
    if core_count <= 0:
        return None
    return {
        "target_on_demand": core_count,
        "target_spot": 0,
        "instance_types": instance_family_fallbacks(node_type_id),
    }


def build_task_fleet_block(task_count: int, node_type_id: str, *, use_spot: bool):
    if task_count <= 0:
        return None
    block = {"instance_types": instance_family_fallbacks(node_type_id)}
    if use_spot:
        block["target_on_demand"] = 0
        block["target_spot"] = task_count
        block.update(_FLEET_SPOT_DEFAULTS)
    else:
        block["target_on_demand"] = task_count
        block["target_spot"] = 0
    return block


def build_zero_capacity_fleet_block(node_type_id: str) -> dict:
    return {
        "target_on_demand": 0,
        "target_spot": 0,
        "instance_types": instance_family_fallbacks(node_type_id),
    }


def effective_to_fleet_topology(effective: dict) -> dict:
    master, core_count, task_count, core_type, task_type = extract_group_topology(
        effective
    )
    use_spot = task_uses_spot(effective)
    result = {"master_node_type_id": master}
    result["core_nodes"] = (
        build_core_fleet_block(core_count, core_type)
        if core_count > 0
        else build_zero_capacity_fleet_block(core_type)
    )
    result["task_nodes"] = (
        build_task_fleet_block(task_count, task_type, use_spot=use_spot)
        if task_count > 0
        else build_zero_capacity_fleet_block(task_type)
    )
    return result


def strip_group_topology_keys(custom: dict) -> None:
    for key in ("num_workers", "num_task_workers", "node_type_id", "task_node_type_id"):
        custom.pop(key, None)
    for name in ("core_nodes", "task_nodes"):
        block = custom.get(name)
        if isinstance(block, dict):
            cleaned = {
                k: v
                for k, v in block.items()
                if k not in {"node_type_id", "instance_count"}
            }
            if cleaned:
                custom[name] = cleaned
            else:
                custom.pop(name, None)


def fleet_override_diff(preset_fleet: dict, effective_fleet: dict) -> dict:
    custom = {}
    for key in ("master_node_type_id",):
        preset_val = preset_fleet.get(key)
        effective_val = effective_fleet.get(key)
        if effective_val and effective_val != preset_val:
            custom[key] = effective_val
    for block_name in ("core_nodes", "task_nodes"):
        preset_block = preset_fleet.get(block_name)
        effective_block = effective_fleet.get(block_name)
        if effective_block != preset_block:
            if effective_block is not None:
                custom[block_name] = copy.deepcopy(effective_block)
            elif preset_block is not None:
                custom[block_name] = {}

    task_custom = custom.get("task_nodes")
    if isinstance(task_custom, dict):
        task_target = int(task_custom.get("target_on_demand", 0) or 0) + int(
            task_custom.get("target_spot", 0) or 0
        )
        if task_target > 0 and "core_nodes" not in custom:
            core_block = effective_fleet.get("core_nodes")
            if isinstance(core_block, dict):
                custom["core_nodes"] = copy.deepcopy(core_block)

    return custom
