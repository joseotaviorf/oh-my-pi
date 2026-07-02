#!/usr/bin/env python3
"""Add parallel emr_7_12_*_fleet_cluster presets alongside existing group presets."""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

_COMPILER_ROOT = Path(__file__).resolve().parents[2]
_REPO_ROOT = Path(__file__).resolve().parents[4]
if str(_COMPILER_ROOT) not in sys.path:
    sys.path.insert(0, str(_COMPILER_ROOT))

from bietlejuice.services.configuration_service import (
    ConfigurationService,  # noqa: E402
)
from scripts.validation.emr_fleet_conversion import (
    effective_to_fleet_topology,  # noqa: E402
)

CONFIG_ROOT = _REPO_ROOT / "packages/bietlejuice-core/src/bietlejuice/config"
FLEET_ANCHOR_ALIAS = "emr_fleet_consolidation_anchor"
_NODE_BLOCK_RE = {
    name: re.compile(rf"^    {name}:\n(?:        [^\n]+\n)*", re.MULTILINE)
    for name in ("core_nodes", "task_nodes")
}


def _format_fleet_block(block: dict) -> str:
    lines: list[str] = []
    for key in (
        "target_on_demand",
        "target_spot",
        "allocation_strategy",
        "bid_price_percentage",
    ):
        if key in block:
            lines.append(f"{key}: {block[key]}")
    if "instance_types" in block:
        lines.append("instance_types:")
        for it in block["instance_types"]:
            lines.append(f"    - {it}")
    return "\n".join(f"        {line}" for line in lines)


def _extract_preset_block(text: str, preset_name: str) -> tuple[int, int, str]:
    pattern = re.compile(rf"^{re.escape(preset_name)}:\n", re.MULTILINE)
    match = pattern.search(text)
    if not match:
        raise ValueError(f"preset not found: {preset_name}")
    start = match.start()
    rest = text[start + len(match.group(0)) :]
    end_offset = len(rest)
    for next_match in re.finditer(r"^[a-zA-Z][a-zA-Z0-9_]*:", rest, re.MULTILINE):
        end_offset = next_match.start()
        break
    end = start + len(match.group(0)) + end_offset
    return start, end, text[start:end]


def _replace_nodes_in_block(block: str, fleet: dict) -> str:
    result = block
    for node_re in _NODE_BLOCK_RE.values():
        result = node_re.sub("", result)

    insert_lines: list[str] = []
    for name in ("core_nodes", "task_nodes"):
        fleet_block = fleet.get(name)
        if fleet_block:
            insert_lines.append(f"    {name}:")
            insert_lines.append(_format_fleet_block(fleet_block))
    if not insert_lines:
        return result

    snippet = "\n".join(insert_lines) + "\n"
    spark_match = re.search(r"^    spark_conf:", result, re.MULTILINE)
    if spark_match:
        pos = spark_match.start()
        return result[:pos] + snippet + result[pos:]
    master_match = re.search(r"^    master_node_type_id:", result, re.MULTILINE)
    if master_match:
        line_end = result.find("\n", master_match.end())
        pos = line_end + 1 if line_end >= 0 else master_match.end()
        return result[:pos] + snippet + result[pos:]
    anchor_match = re.search(r"^    <<: \*", result, re.MULTILINE)
    if anchor_match:
        line_end = result.find("\n", anchor_match.end())
        pos = line_end + 1 if line_end >= 0 else anchor_match.end()
        return result[:pos] + snippet + result[pos:]
    return result.rstrip() + "\n" + snippet


def _group_to_fleet_preset_name(group_name: str) -> str:
    if not group_name.endswith("_cluster"):
        raise ValueError(f"expected group preset ending in _cluster: {group_name}")
    return group_name[: -len("_cluster")] + "_fleet_cluster"


def add_fleet_anchor(text: str) -> str:
    if "emr_fleet_consolidation_base" in text:
        return text
    marker = "emr_spark_single_node: &emr_spark_single_node"
    insert = """emr_fleet_consolidation_base: &emr_fleet_consolidation_anchor
    <<: *emr_cluster_anchor
    aws_attributes:
        <<: *emr_aws_anchor
        availability: ON_DEMAND
        task_availability: SPOT

"""
    if marker not in text:
        raise ValueError("emr_spark_single_node anchor not found")
    return text.replace(marker, insert + marker, 1)


def swap_consolidation_anchor_in_block(block: str) -> str:
    return block.replace("<<: *emr_consolidation_anchor", f"<<: *{FLEET_ANCHOR_ALIAS}")


def list_emr_group_presets(text: str) -> list[str]:
    names = re.findall(r"^(emr_7_12_[a-z0-9_]+):", text, re.MULTILINE)
    return [
        name
        for name in names
        if name.endswith("_cluster") and not name.endswith("_fleet_cluster")
    ]


def build_fleet_preset_block(group_block: str, fleet_name: str, fleet: dict) -> str:
    block = group_block
    block = re.sub(
        r"^emr_7_12_[a-z0-9_]+:",
        f"{fleet_name}:",
        block,
        count=1,
        flags=re.MULTILINE,
    )
    block = swap_consolidation_anchor_in_block(block)
    return _replace_nodes_in_block(block, fleet)


def convert_conf(path: Path, environment: str, *, dry_run: bool) -> int:
    os.environ["ENVIRONMENT"] = environment
    ConfigurationService._instance_cache.clear()
    config_service = ConfigurationService()
    text = path.read_text()
    text = add_fleet_anchor(text)
    changed = 0
    for preset in list_emr_group_presets(text):
        fleet_name = _group_to_fleet_preset_name(preset)
        if re.search(rf"^{re.escape(fleet_name)}:\n", text, re.MULTILINE):
            continue
        try:
            effective = config_service.get_config(preset)
        except Exception:
            continue
        if not isinstance(effective, dict):
            continue
        try:
            fleet = effective_to_fleet_topology(effective)
        except ValueError:
            continue
        _start, end, group_block = _extract_preset_block(text, preset)
        fleet_block = build_fleet_preset_block(group_block, fleet_name, fleet)
        text = text[:end] + fleet_block + text[end:]
        changed += 1
    if not dry_run:
        path.write_text(text)
    print(f"{path.name} ({environment}): added {changed} fleet presets")
    return changed


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    convert_conf(CONFIG_ROOT / "prod_conf.yml", "prod", dry_run=args.dry_run)
    convert_conf(CONFIG_ROOT / "forno_conf.yml", "forno", dry_run=args.dry_run)


if __name__ == "__main__":
    main()
