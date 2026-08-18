#!/usr/bin/env python3
"""
Promote a Databricks-prod / EMR-validation DAG to EMR-prod (batch 95).

Unlike promote_cluster_validation_to_prod.py (EMR gen6 -> gen7 promotion, which copies
prod's `custom_configurations` through verbatim), this targets a *_cluster.yml that still
runs Databricks in prod with an EMR `validation:` block that has already passed a
`bietlejuice.<dag>__validation` run. It reuses `merge_validation_cluster_args` -- the same
function the validation DAG used at compile time -- so prod ends up running the exact spec
that was validated, not a hand-remerged approximation.

Databricks-only keys are stripped by merge_validation_cluster_args itself
(databricks_conn_id, spark_version, single_user_name, data_security_mode, runtime_engine,
node_type_id/driver_node_type_id/num_workers, spark.databricks.* except
spark.databricks.delta.*). This script additionally drops `access_control_list`, which has
no effect on EMR (only read by databricks_plugin operators).

Usage:
  python packages/bietlejuice-compiler/scripts/validation/promote_databricks_validation_to_emr.py dags/growth/
  python packages/bietlejuice-compiler/scripts/validation/promote_databricks_validation_to_emr.py dags/growth/ --dry-run
  python packages/bietlejuice-compiler/scripts/validation/promote_databricks_validation_to_emr.py dags/growth/ \\
      --only ada_crawls,amplitude_new
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import List, Optional, Set

import yaml

REPO_ROOT = Path(__file__).resolve().parents[4]
_COMPILER_ROOT = Path(__file__).resolve().parents[2]
if str(_COMPILER_ROOT) not in sys.path:
    sys.path.insert(0, str(_COMPILER_ROOT))

from bietlejuice.base.validation.cluster_args import merge_validation_cluster_args
from scripts.ci_cd.airflow_dag_builder.cluster_yaml_format import (
    assert_no_folded_catalog_namespace,
    dump_cluster_yaml,
)

# Keys that only mean something to Databricks job-cluster ACLs; EMR ignores them entirely.
_DATABRICKS_ONLY_TOP_LEVEL_KEYS = ("access_control_list",)


def _cluster_paths(root: Path) -> List[Path]:
    return sorted(root.rglob("*_cluster.yml"))


def _dag_name_from_cluster_path(cluster_path: Path) -> str:
    return cluster_path.name[: -len("_cluster.yml")]


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

    merged = merge_validation_cluster_args(prod_cluster, validation_cluster)
    for key in _DATABRICKS_ONLY_TOP_LEVEL_KEYS:
        merged.pop(key, None)

    cluster_type = str(merged.get("type", ""))
    if not cluster_type.startswith("emr_"):
        raise ValueError(
            f"{cluster_path}: promoted cluster.type {cluster_type!r} is not an EMR "
            "preset -- refusing to promote (validation.cluster.type must start with "
            "'emr_')"
        )

    new_document = {"cluster": merged}
    if "spark_session_configs" in document:
        new_document["spark_session_configs"] = document["spark_session_configs"]

    new_text = dump_cluster_yaml(new_document)
    assert_no_folded_catalog_namespace(new_text)

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
        "--only",
        dest="only",
        help=(
            "Comma-separated DAG names to restrict promotion to (matched against the "
            "*_cluster.yml stem). Required in practice: only promote DAGs with a "
            "successful __validation run on record."
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print files that would be promoted without writing",
    )
    args = parser.parse_args(argv)

    only: Optional[Set[str]] = None
    if args.only:
        only = {name.strip() for name in args.only.split(",") if name.strip()}

    os.environ.setdefault("ENVIRONMENT", "prod")

    promoted = 0
    skipped_no_validation = 0
    for raw_path in args.paths:
        root = (REPO_ROOT / raw_path).resolve()
        if not root.exists():
            print(f"Skip missing path: {raw_path}", file=sys.stderr)
            continue
        for cluster_path in _cluster_paths(root):
            dag_name = _dag_name_from_cluster_path(cluster_path)
            if only is not None and dag_name not in only:
                continue
            if promote_cluster_file(cluster_path, dry_run=args.dry_run):
                promoted += 1
            else:
                skipped_no_validation += 1
                if only is not None:
                    print(
                        f"Skip (no validation.cluster): {_display_path(cluster_path)}",
                        file=sys.stderr,
                    )

    if only is not None:
        missing = only - {
            _dag_name_from_cluster_path(p)
            for raw_path in args.paths
            for p in _cluster_paths((REPO_ROOT / raw_path).resolve())
            if (REPO_ROOT / raw_path).resolve().exists()
        }
        if missing:
            print(
                f"Names in --only never matched a cluster file: {sorted(missing)}",
                file=sys.stderr,
            )

    status = "Would promote" if args.dry_run else "Promoted"
    print(f"{status} {promoted} cluster file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
