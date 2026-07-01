#!/usr/bin/env python3
"""
Rebalance EMR core/task topology and align instance generations in *_cluster.yml.

Usage:
  uv run python packages/bietlejuice-compiler/scripts/validation/migrate_emr_topology_and_gen.py dags/
  uv run python packages/bietlejuice-compiler/scripts/validation/migrate_emr_topology_and_gen.py dags/ --dry-run
"""

from __future__ import annotations

import argparse
import copy
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

REPO_ROOT = Path(__file__).resolve().parents[4]
_COMPILER_ROOT = Path(__file__).resolve().parents[2]
if str(_COMPILER_ROOT) not in sys.path:
    sys.path.insert(0, str(_COMPILER_ROOT))

from bietlejuice.base.airflow.cluster_config_resolver import merge_cluster_configuration
from bietlejuice.services.configuration_service import ConfigurationService
from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (
    emr_worker_core_task_split,
    is_single_node_cluster,
    map_instance_type_to_emr_gen6,
    normalize_emr_cluster_topology,
    strip_redundant_preset_default_overrides,
)
from scripts.ci_cd.airflow_dag_builder.cluster_yaml_format import (
    assert_no_folded_catalog_namespace,
    cluster_file_documents_equal,
    dump_cluster_yaml,
)

_TOPOLOGY_KEYS = (
    "master_node_type_id",
    "node_type_id",
    "task_node_type_id",
    "driver_node_type_id",
)
_NESTED_TOPOLOGY = (
    ("core_nodes", "node_type_id"),
    ("task_nodes", "node_type_id"),
)


@dataclass
class MigrationStats:
    changed: int = 0
    skipped: int = 0
    actions: Dict[str, int] = field(default_factory=dict)


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


def _is_emr_cluster_block(cluster: dict) -> bool:
    return str(cluster.get("type", "")).startswith("emr_")


def _bump_topology_value(instance_type: str) -> str:
    return map_instance_type_to_emr_gen6(instance_type)


def _bump_custom_topology(custom: dict[str, Any]) -> bool:
    changed = False
    for key in _TOPOLOGY_KEYS:
        raw = custom.get(key)
        if isinstance(raw, str) and raw.strip():
            bumped = _bump_topology_value(raw)
            if bumped != raw:
                custom[key] = bumped
                changed = True
    for parent, child in _NESTED_TOPOLOGY:
        section = custom.get(parent)
        if isinstance(section, dict):
            raw = section.get(child)
            if isinstance(raw, str) and raw.strip():
                bumped = _bump_topology_value(raw)
                if bumped != raw:
                    section[child] = bumped
                    changed = True
    return changed


def _worker_counts(effective: dict[str, Any]) -> tuple[int, int]:
    core = int((effective.get("core_nodes") or {}).get("instance_count", 0) or 0)
    task = int((effective.get("task_nodes") or {}).get("instance_count", 0) or 0)
    return core, task


def migrate_emr_cluster_block(
    cluster_args: dict[str, Any],
    config_service: ConfigurationService,
) -> tuple[dict[str, Any], List[str]]:
    if not _is_emr_cluster_block(cluster_args):
        return cluster_args, []

    actions: List[str] = []
    updated = normalize_emr_cluster_topology(copy.deepcopy(cluster_args))
    effective = merge_cluster_configuration(updated, config_service)

    if not is_single_node_cluster(effective):
        core, task = _worker_counts(effective)
        total = core + task
        if total >= 2:
            new_core, new_task = emr_worker_core_task_split(total)
            if (new_core, new_task) != (core, task):
                custom = updated.setdefault("custom_configurations", {})
                if not isinstance(custom, dict):
                    custom = {}
                    updated["custom_configurations"] = custom
                core_nodes = custom.setdefault("core_nodes", {})
                task_nodes = custom.setdefault("task_nodes", {})
                if isinstance(core_nodes, dict):
                    core_nodes["instance_count"] = new_core
                if isinstance(task_nodes, dict):
                    task_nodes["instance_count"] = new_task
                actions.append("rebalanced")

    custom = updated.get("custom_configurations")
    if isinstance(custom, dict) and _bump_custom_topology(custom):
        actions.append("gen_bumped")

    stripped = strip_redundant_preset_default_overrides(updated, config_service)
    if stripped != updated and "rebalanced" not in actions:
        actions.append("stripped_redundant")
    updated = stripped
    return updated, actions


def migrate_cluster_file(
    cluster_path: Path,
    config_service: ConfigurationService,
    *,
    dry_run: bool = False,
) -> Optional[List[str]]:
    document = yaml.safe_load(cluster_path.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        return None

    new_document: Dict[str, Any] = {}
    file_actions: List[str] = []

    cluster = document.get("cluster")
    if isinstance(cluster, dict) and _is_emr_cluster_block(cluster):
        new_cluster, actions = migrate_emr_cluster_block(cluster, config_service)
        new_document["cluster"] = new_cluster
        file_actions.extend(actions)
    elif isinstance(cluster, dict):
        new_document["cluster"] = copy.deepcopy(cluster)

    validation = document.get("validation")
    if isinstance(validation, dict):
        new_validation = copy.deepcopy(validation)
        val_cluster = new_validation.get("cluster")
        if isinstance(val_cluster, dict) and _is_emr_cluster_block(val_cluster):
            new_val_cluster, actions = migrate_emr_cluster_block(
                val_cluster, config_service
            )
            new_validation["cluster"] = new_val_cluster
            file_actions.extend(actions)
        if new_validation:
            new_document["validation"] = new_validation

    for key in ("spark_session_configs",):
        if key in document:
            new_document[key] = document[key]

    if not file_actions:
        return None

    new_text = dump_cluster_yaml(new_document)
    assert_no_folded_catalog_namespace(new_text)
    old_text = cluster_path.read_text(encoding="utf-8")
    if cluster_file_documents_equal(old_text, new_text):
        return None

    label = _display_path(cluster_path)
    action_summary = ",".join(sorted(set(file_actions)))
    if dry_run:
        print(f"Would migrate ({action_summary}): {label}")
    else:
        cluster_path.write_text(new_text, encoding="utf-8")
        print(f"Migrated ({action_summary}): {label}")

    return file_actions


def _display_path(cluster_path: Path) -> str:
    try:
        return cluster_path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return cluster_path.as_posix()


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
        help="Only migrate cluster files whose path contains this substring",
    )
    parser.add_argument(
        "--exclude",
        dest="exclude_substring",
        help="Skip cluster files whose path contains this substring",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print files that would change without writing",
    )
    args = parser.parse_args(argv)

    os.environ.setdefault("ENVIRONMENT", "prod")
    ConfigurationService._instance_cache.clear()
    config_service = ConfigurationService()

    stats = MigrationStats()
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
            actions = migrate_cluster_file(
                cluster_path, config_service, dry_run=args.dry_run
            )
            if actions is None:
                stats.skipped += 1
                continue
            stats.changed += 1
            for action in set(actions):
                stats.actions[action] = stats.actions.get(action, 0) + 1

    print(
        f"Done: changed={stats.changed} skipped={stats.skipped} "
        f"actions={dict(sorted(stats.actions.items()))}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
