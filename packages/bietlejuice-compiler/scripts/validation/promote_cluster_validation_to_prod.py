#!/usr/bin/env python3
"""
Promote validation.cluster to prod cluster: and remove validation: block (PR2 migration).

Usage:
  python packages/bietlejuice-compiler/scripts/validation/promote_cluster_validation_to_prod.py dags/core/
  python packages/bietlejuice-compiler/scripts/validation/promote_cluster_validation_to_prod.py dags/platform/alert_manager/
  python packages/bietlejuice-compiler/scripts/validation/promote_cluster_validation_to_prod.py --glob 'dags/**/*_fast_lane/'
"""

from __future__ import annotations

import argparse
import copy
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

REPO_ROOT = Path(__file__).resolve().parents[4]

# Preset owns worker/driver when validation custom_configurations omits these keys.
_TOPOLOGY_KEYS = ("node_type_id", "driver_node_type_id")

# Prevent yaml.dump from folding long spark_conf keys (e.g. Jinja catalog.namespace).
_YAML_DUMP_WIDTH = 10_000


def _deep_merge(base: dict, overlay: dict) -> dict:
    merged = copy.deepcopy(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = copy.deepcopy(value)
    return merged


def merge_promoted_cluster(prod_cluster: dict, validation_cluster: dict) -> dict:
    """Promote validation preset while preserving prod-only cluster overlays."""
    merged = copy.deepcopy(validation_cluster)
    prod_custom = prod_cluster.get("custom_configurations") or {}
    val_custom = merged.get("custom_configurations") or {}
    merged_custom = _deep_merge(prod_custom, val_custom)
    for key in _TOPOLOGY_KEYS:
        if key not in val_custom and key in merged_custom:
            del merged_custom[key]
    if merged_custom:
        merged["custom_configurations"] = merged_custom
    elif "custom_configurations" in merged:
        del merged["custom_configurations"]
    for key, value in prod_cluster.items():
        if key in ("type", "custom_configurations"):
            continue
        if key not in merged:
            merged[key] = copy.deepcopy(value)
    return merged


def _cluster_paths(root: Path) -> List[Path]:
    return sorted(root.rglob("*_cluster.yml"))


def _matches_filter(
    cluster_path: Path, name_filter: Optional[str], exclude: Optional[str]
) -> bool:
    rel = cluster_path.relative_to(REPO_ROOT).as_posix()
    if name_filter is not None and name_filter not in rel:
        return False
    if exclude is not None and exclude in rel:
        return False
    return True


def promote_cluster_file(cluster_path: Path, *, dry_run: bool = False) -> bool:
    text = cluster_path.read_text(encoding="utf-8")
    document = yaml.safe_load(text)
    if not isinstance(document, dict):
        return False

    validation = document.get("validation")
    if not validation or not isinstance(validation, dict):
        return False

    validation_cluster = validation.get("cluster")
    if not validation_cluster or not isinstance(validation_cluster, dict):
        raise ValueError(f"{cluster_path}: validation block missing cluster mapping")

    prod_cluster = document.get("cluster") or {}
    if not isinstance(prod_cluster, dict):
        prod_cluster = {}

    new_document: Dict[str, Any] = {
        "cluster": merge_promoted_cluster(prod_cluster, validation_cluster)
    }
    if "spark_session_configs" in document:
        new_document["spark_session_configs"] = document["spark_session_configs"]

    new_text = yaml.dump(
        new_document,
        default_flow_style=False,
        sort_keys=False,
        allow_unicode=True,
        width=_YAML_DUMP_WIDTH,
    )
    if not new_text.endswith("\n"):
        new_text += "\n"

    if dry_run:
        print(f"Would promote: {_display_path(cluster_path)}")
        return True

    cluster_path.write_text(new_text, encoding="utf-8")
    print(f"Promoted: {_display_path(cluster_path)}")
    return True


def _display_path(cluster_path: Path) -> str:
    try:
        return cluster_path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(cluster_path)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="*",
        default=["dags/"],
        help="DAG subtree roots (default: dags/)",
    )
    parser.add_argument(
        "--filter",
        dest="name_filter",
        help="Only promote cluster files whose path contains this substring",
    )
    parser.add_argument(
        "--exclude",
        dest="exclude_substring",
        help="Skip cluster files whose path contains this substring",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print files that would be promoted without writing",
    )
    args = parser.parse_args(argv)

    promoted = 0
    for raw_path in args.paths:
        root = (REPO_ROOT / raw_path).resolve()
        if not root.exists():
            print(f"Skip missing path: {raw_path}", file=sys.stderr)
            continue
        for cluster_path in _cluster_paths(root):
            if not _matches_filter(
                cluster_path, args.name_filter, args.exclude_substring
            ):
                continue
            if promote_cluster_file(cluster_path, dry_run=args.dry_run):
                promoted += 1

    status = "Would promote" if args.dry_run else "Promoted"
    print(f"{status} {promoted} cluster file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
