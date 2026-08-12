#!/usr/bin/env python3
"""Fail if a changed DAG cannot be built with prod config (parse-time gate).

Builds each affected declaration through the same FactoryDispatcher path the
Astro domain bundle uses, so a green gate means a green bundle. A DAG that
fails to build is quarantined at runtime (tag ``broken-dag``) and does not
schedule — catch it here instead of in production.

Usage (CI):
    python validate_dag_builds.py -b "$CI_COMMIT_BRANCH"

Usage (local audit — build every declaration, exit 0):
    python validate_dag_builds.py -a
"""

from __future__ import annotations

import argparse
import os
import sys
import traceback
from pathlib import Path

# Repo root (``dags``), compiler scripts (``services``), and Airflow operators
# (``databricks_plugin``) are not always on the ``uv run --project`` path in CI.
REPO_ROOT = Path(__file__).resolve().parents[5]
_SCRIPTS_ROOT = Path(__file__).resolve().parents[2]
_OPERATORS_SRC = REPO_ROOT / "packages" / "bietlejuice-airflow-operators" / "src"
for _path in (REPO_ROOT, _SCRIPTS_ROOT, _OPERATORS_SRC):
    _path_str = str(_path)
    if _path_str not in sys.path:
        sys.path.insert(0, _path_str)

from services.git_service import GitService

from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser import (
    DAGYamlParser,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher import (
    FactoryDispatcher,
)
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref
from bietlejuice.services.configuration_service import ConfigurationService

# Include deletes: removing ``*_cluster.yml`` (etc.) while leaving the
# declaration can still break parse-time builds. Same posture as
# ``validate_no_new_databricks_clusters.RELEVANT_STATUSES``.
_RELEVANT_STATUSES = frozenset({"A", "M", "D"})


def affected_dag_names(changed_files: dict[str, str]) -> list[str]:
    """DAG names whose folder had an A/M/D file, excluding the luigijr sandbox.

    Fully deleted DAGs are skipped because the declaration is gone on HEAD;
    delete-only edits that leave the declaration (e.g. cluster YAML removal)
    are still build-checked.
    """
    names = set()
    for path_str, status in changed_files.items():
        if status not in _RELEVANT_STATUSES:
            continue
        if not path_str.startswith("dags/") or path_str.startswith("dags/luigijr/"):
            continue
        parts = Path(path_str).parts
        if len(parts) < 3:
            continue
        dag_root = REPO_ROOT / parts[0] / parts[1] / parts[2]
        dag_name = parts[2]
        if (dag_root / f"{dag_name}_declaration.yml").is_file():
            names.add(dag_name)
    return sorted(names)


def build_dag(dag_name: str) -> None:
    declaration = DAGYamlParser(dag_name=dag_name).dag_declaration()
    factory = FactoryDispatcher(
        layer=LayerEnum(declaration["workflow"]["layer"])
    ).get_factory(
        dag_args=declaration["dag"],
        workflow_args=declaration["workflow"],
        cluster_args=declaration["cluster"],
        dataset_dependencies=None,
    )
    factory.get_workflow().build_dag()


def collect_failures(dag_names: list[str]) -> list[tuple[str, str]]:
    failures: list[tuple[str, str]] = []
    for dag_name in dag_names:
        try:
            build_dag(dag_name)
        except Exception as exc:  # noqa: BLE001 — report every broken DAG
            failures.append((dag_name, f"{type(exc).__name__}: {exc}"))
            traceback.print_exc()
    return failures


def all_declaration_dag_names() -> list[str]:
    names = set()
    for decl in sorted(REPO_ROOT.glob("dags/*/*/*_declaration.yml")):
        if "luigijr" in decl.parts:
            continue
        names.add(decl.name[: -len("_declaration.yml")])
    return sorted(names)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Fail if a changed DAG cannot be built with prod config."
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("-b", "--branch", help="Current branch (CI_COMMIT_BRANCH)")
    group.add_argument(
        "-a",
        "--all-files",
        action="store_true",
        help="Build every DAG with prod config (local audit, exit 0)",
    )
    return parser.parse_args()


def main() -> int:
    os.environ.setdefault("ENVIRONMENT", "prod")
    ConfigurationService._instance_cache.clear()

    args = parse_args()

    if args.all_files:
        dag_names = all_declaration_dag_names()
        failures = collect_failures(dag_names)
        print(f"Built {len(dag_names)} DAG(s); {len(failures)} failure(s).")
        for dag_name, message in failures:
            print(f"  {dag_name}: {message}")
        return 0

    git_service = GitService()
    from_ref = resolve_diff_from_ref(args.branch)
    changed = git_service.get_modified_files_from_diff(from_ref, "HEAD")
    dag_names = affected_dag_names(changed)
    if not dag_names:
        print("OK: No changed declaration DAGs to build.")
        return 0

    print(f"Building {len(dag_names)} changed DAG(s) with prod config...")
    failures = collect_failures(dag_names)
    if not failures:
        print("OK: All changed DAGs build with prod config.")
        return 0

    print(
        f"\nFound {len(failures)} DAG(s) that fail to build with prod config:\n",
        file=sys.stderr,
    )
    for dag_name, message in failures:
        print(f"  {dag_name}: {message}", file=sys.stderr)
    print(
        "\nA DAG that fails to build is quarantined at runtime (tag 'broken-dag') and does\n"
        "not schedule. Fix the declaration/cluster config before merging.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
