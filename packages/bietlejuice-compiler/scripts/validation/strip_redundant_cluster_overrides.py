#!/usr/bin/env python3
"""
Strip redundant preset-default topology echoes from *_cluster.yml files.

Usage:
  python packages/bietlejuice-compiler/scripts/validation/strip_redundant_cluster_overrides.py dags/
  python packages/bietlejuice-compiler/scripts/validation/strip_redundant_cluster_overrides.py dags/ --dry-run
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
    find_redundant_preset_default_overrides,
    strip_redundant_preset_default_overrides,
)
from scripts.ci_cd.airflow_dag_builder.cluster_yaml_format import (
    assert_no_folded_catalog_namespace,
    dump_cluster_yaml,
)


@dataclass
class StripStats:
    updated: int = 0
    skipped: int = 0


def _cluster_paths(root: Path) -> List[Path]:
    return sorted(root.rglob("*_cluster.yml"))


def _strip_cluster_block(
    cluster: dict[str, Any], config_service: ConfigurationService
) -> tuple[dict[str, Any], bool]:
    if not isinstance(cluster, dict) or not cluster.get("type"):
        return cluster, False
    before = find_redundant_preset_default_overrides(cluster, config_service)
    if not before:
        return cluster, False
    return strip_redundant_preset_default_overrides(cluster, config_service), True


def strip_cluster_file(
    cluster_path: Path,
    config_service: ConfigurationService,
    *,
    dry_run: bool = False,
) -> bool:
    document = yaml.safe_load(cluster_path.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        return False

    new_document: Dict[str, Any] = copy.deepcopy(document)
    changed = False

    cluster = new_document.get("cluster")
    if isinstance(cluster, dict):
        stripped, block_changed = _strip_cluster_block(cluster, config_service)
        if block_changed:
            new_document["cluster"] = stripped
            changed = True

    validation = new_document.get("validation")
    if isinstance(validation, dict):
        validation_cluster = validation.get("cluster")
        if isinstance(validation_cluster, dict):
            stripped, block_changed = _strip_cluster_block(
                validation_cluster, config_service
            )
            if block_changed:
                validation["cluster"] = stripped
                changed = True

    if not changed:
        return False

    new_text = dump_cluster_yaml(new_document)
    assert_no_folded_catalog_namespace(new_text)

    rel = cluster_path.relative_to(REPO_ROOT).as_posix()
    if dry_run:
        print(f"Would strip: {rel}")
    else:
        cluster_path.write_text(new_text, encoding="utf-8")
        print(f"Stripped: {rel}")
    return True


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "path",
        nargs="?",
        default="dags/",
        help="DAG subtree to scan (default: dags/)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print files that would change without writing",
    )
    args = parser.parse_args(argv)

    os.environ.setdefault("ENVIRONMENT", "prod")
    ConfigurationService._instance_cache.clear()

    scan_root = REPO_ROOT / args.path
    config_service = ConfigurationService()
    stats = StripStats()

    for cluster_path in _cluster_paths(scan_root):
        if strip_cluster_file(cluster_path, config_service, dry_run=args.dry_run):
            stats.updated += 1
        else:
            stats.skipped += 1

    action = "Would update" if args.dry_run else "Updated"
    print(f"\n{action} {stats.updated} file(s); skipped {stats.skipped}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
