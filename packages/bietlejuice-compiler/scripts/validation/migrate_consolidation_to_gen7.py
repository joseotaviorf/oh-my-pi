#!/usr/bin/env python3
"""
Fleet Gen7 migration for consolidation DAG cluster YAML files.

Usage:
  python packages/bietlejuice-compiler/scripts/validation/migrate_consolidation_to_gen7.py dags/
  python packages/bietlejuice-compiler/scripts/validation/migrate_consolidation_to_gen7.py dags/ --dry-run
"""

from __future__ import annotations

import argparse
import copy
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

REPO_ROOT = Path(__file__).resolve().parents[4]
_COMPILER_ROOT = Path(__file__).resolve().parents[2]
if str(_COMPILER_ROOT) not in sys.path:
    sys.path.insert(0, str(_COMPILER_ROOT))

from bietlejuice.services.configuration_service import ConfigurationService
from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (
    bump_cluster_topology_to_gen7,
    is_consolidation_cluster_type,
    normalize_databricks_cluster_topology,
)
from scripts.ci_cd.airflow_dag_builder.cluster_yaml_format import (
    assert_no_folded_catalog_namespace,
    dump_cluster_yaml,
)
from scripts.validation.promote_cluster_validation_to_prod import merge_promoted_cluster


@dataclass
class MigrationStats:
    promoted: int = 0
    bumped: int = 0
    validation_kept: int = 0
    skipped: int = 0


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


def _finalize_prod_cluster(
    cluster: dict[str, Any],
    config_service: ConfigurationService,
) -> dict[str, Any]:
    bumped = bump_cluster_topology_to_gen7(cluster)
    normalized = normalize_databricks_cluster_topology(bumped, config_service)
    return normalized


def migrate_cluster_file(
    cluster_path: Path,
    config_service: ConfigurationService,
    *,
    dry_run: bool = False,
) -> Optional[str]:
    """
    Migrate one cluster YAML file. Returns action label or None when skipped.
    """
    document = yaml.safe_load(cluster_path.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        return None

    prod_cluster = document.get("cluster") or {}
    if not isinstance(prod_cluster, dict):
        prod_cluster = {}

    validation = document.get("validation")
    validation_cluster = None
    if isinstance(validation, dict):
        validation_cluster = validation.get("cluster")

    prod_type = str(prod_cluster.get("type", ""))
    val_type = (
        str(validation_cluster.get("type", ""))
        if isinstance(validation_cluster, dict)
        else ""
    )

    prod_is_consolidation = is_consolidation_cluster_type(prod_type)
    val_is_consolidation = is_consolidation_cluster_type(val_type)

    if not prod_is_consolidation and not val_is_consolidation:
        return None

    new_document: Dict[str, Any] = {}
    action: Optional[str] = None

    if prod_is_consolidation and isinstance(validation, dict) and validation_cluster:
        promoted = merge_promoted_cluster(prod_cluster, validation_cluster)
        new_document["cluster"] = _finalize_prod_cluster(promoted, config_service)
        action = "promoted"
    elif prod_is_consolidation:
        new_document["cluster"] = _finalize_prod_cluster(prod_cluster, config_service)
        action = "bumped"
    else:
        new_document["cluster"] = copy.deepcopy(prod_cluster)
        action = "validation_kept"

    if isinstance(validation, dict) and action == "validation_kept":
        kept_validation = copy.deepcopy(validation)
        if isinstance(kept_validation.get("cluster"), dict):
            kept_validation["cluster"] = _finalize_prod_cluster(
                kept_validation["cluster"], config_service
            )
        new_document["validation"] = kept_validation

    if "spark_session_configs" in document:
        new_document["spark_session_configs"] = document["spark_session_configs"]

    if action is None:
        return None

    new_text = dump_cluster_yaml(new_document)
    assert_no_folded_catalog_namespace(new_text)

    if dry_run:
        label = _display_path(cluster_path)
        print(f"Would {action}: {label}")
    else:
        cluster_path.write_text(new_text, encoding="utf-8")
        print(f"{action.capitalize()}: {_display_path(cluster_path)}")

    return action


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
            action = migrate_cluster_file(
                cluster_path, config_service, dry_run=args.dry_run
            )
            if action is None:
                stats.skipped += 1
            elif action == "promoted":
                stats.promoted += 1
            elif action == "bumped":
                stats.bumped += 1
            elif action == "validation_kept":
                stats.validation_kept += 1

    prefix = "Would migrate" if args.dry_run else "Migrated"
    print(
        f"{prefix}: promoted={stats.promoted} bumped={stats.bumped} "
        f"validation_kept={stats.validation_kept} skipped={stats.skipped}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
