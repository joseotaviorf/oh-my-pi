#!/usr/bin/env python3
"""List DAG declarations eligible for validation.cluster opt-in."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
DAGS_ROOT = REPO_ROOT / "dags"

PHASE1_WORKFLOWS = {
    "query_delta",
    "query",
    "dw_query",
    "metric_query",
}

PHASE2_WORKFLOWS = {
    "cdc",
    "custom_ingestion",
    "gsheets",
    "database_pull",
    "database_pull_delta",
    "api_ingestion",
    "dms_cdc",
    "core_model",
    "access",
    "load",
    "load_access",
    "reverse",
    "qube_measure",
    "qube_dimension",
    "qube_metric",
}

SKIP_CLUSTER_PREFIXES = ("emr_",)
ALREADY_CONSOLIDATED_PREFIX = "consolidation_"


def _load_declaration(path: Path) -> dict | None:
    try:
        with path.open() as handle:
            return yaml.safe_load(handle)
    except (OSError, yaml.YAMLError):
        return None


def _has_load_spark_job(declaration: dict) -> bool:
    workflow = declaration.get("workflow", {})
    if workflow.get("load_spark_job"):
        return True
    tables_customization = workflow.get("tables_customization")
    if not isinstance(tables_customization, dict):
        return False
    for table_cfg in tables_customization.values():
        if isinstance(table_cfg, dict) and table_cfg.get("load_spark_job"):
            return True
    return False


def classify(declaration: dict) -> str | None:
    cluster_type = declaration.get("cluster", {}).get("type", "")
    if cluster_type.startswith(SKIP_CLUSTER_PREFIXES):
        return None
    if cluster_type.startswith(ALREADY_CONSOLIDATED_PREFIX):
        return "already_consolidation"
    workflow_type = declaration.get("workflow", {}).get("type", "")
    if workflow_type in PHASE1_WORKFLOWS:
        if _has_load_spark_job(declaration):
            return "phase1_needs_allow_custom_spark_job"
        return "phase1"
    if workflow_type in PHASE2_WORKFLOWS:
        return "phase2"
    return "unsupported"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--phase",
        choices=("1", "2", "all"),
        default="all",
        help="Filter by rollout phase",
    )
    args = parser.parse_args()

    buckets: dict[str, list[str]] = {}
    for path in sorted(DAGS_ROOT.rglob("*_declaration.yml")):
        declaration = _load_declaration(path)
        if not declaration:
            continue
        label = classify(declaration)
        if not label:
            continue
        if args.phase == "1" and not label.startswith("phase1"):
            continue
        if args.phase == "2" and label != "phase2":
            continue
        dag_name = declaration.get("dag", {}).get("name", path.parent.name)
        buckets.setdefault(label, []).append(dag_name)

    for label in sorted(buckets):
        print(f"\n## {label} ({len(buckets[label])})")
        for name in buckets[label]:
            print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
