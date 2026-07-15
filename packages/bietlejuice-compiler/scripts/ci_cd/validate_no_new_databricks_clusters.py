#!/usr/bin/env python3
"""Block new Databricks production cluster deployments in CI.

Fails when a PR introduces a Databricks prod runtime via either:
  1. A brand-new DAG whose production cluster is not EMR, or
  2. An alteration that changes production runtime from EMR → Databricks.

Existing Databricks DAGs may still be edited (Databricks → Databricks).
Engine detection uses both ``cluster.type`` (``emr_*``) and effective
``spark_version`` (``emr-*``), matching Airflow routing.

Bypass: list the DAG in ``databricks_cluster_exceptions.yml`` (owned by
``@quintoandar/data-ingestion-code-owners``).

Usage (CI):
    python validate_no_new_databricks_clusters.py -b "$CI_COMMIT_BRANCH"

Usage (local audit — list all Databricks prod clusters, exit 0):
    python validate_no_new_databricks_clusters.py -a
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, NamedTuple, Optional, Set, Tuple

import yaml

sys.path.append(str(Path(__file__).parent.parent))
from services.git_service import GitService

from bietlejuice.base.airflow.cluster_config_resolver import (
    is_airflow_emr_cluster,
    is_airflow_emr_cluster_type,
    resolve_airflow_compute_mode,
)
from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref
from bietlejuice.services.configuration_service import ConfigurationService

REPO_ROOT = Path(__file__).resolve().parents[4]
EXCEPTIONS_PATH = Path(__file__).resolve().parent / "databricks_cluster_exceptions.yml"
# Include deletes: removing ``*_cluster.yml`` can reveal a legacy inline
# Databricks ``cluster`` on the declaration and silently flip EMR → Databricks.
RELEVANT_STATUSES = frozenset({"A", "M", "D"})


class Violation(NamedTuple):
    dag_root: str
    reason: str
    cluster_type: str
    spark_version: str


@dataclass(frozen=True)
class ClusterClassification:
    is_emr: bool
    cluster_type: str
    spark_version: str


def load_exceptions(path: Path = EXCEPTIONS_PATH) -> Tuple[Set[str], Set[str]]:
    """Return (dag_names, repo_relative_paths) from the exceptions YAML."""
    if not path.exists():
        return set(), set()
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    entries = data.get("exceptions") or []
    dag_names: Set[str] = set()
    paths: Set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        dag = entry.get("dag")
        if dag:
            dag_names.add(str(dag).strip())
        rel = entry.get("path")
        if rel:
            paths.add(str(rel).strip().rstrip("/"))
    return dag_names, paths


def is_excepted(
    dag_name: str,
    dag_root: str,
    dag_names: Set[str],
    paths: Set[str],
) -> bool:
    if dag_name in dag_names:
        return True
    return dag_root.rstrip("/") in paths


def extract_prod_cluster(
    yaml_doc: Any, *, from_cluster_file: bool = True
) -> Optional[dict]:
    """Extract production ``cluster`` args; ignore ``validation``.

    ``from_cluster_file`` is kept for call-site clarity; both cluster YAML and
    declaration YAML use the top-level ``cluster`` key.
    """
    _ = from_cluster_file
    if not isinstance(yaml_doc, dict):
        return None
    cluster = yaml_doc.get("cluster")
    if not isinstance(cluster, dict):
        return None
    return cluster


def parse_yaml_text(text: str) -> Any:
    return yaml.safe_load(text) if text.strip() else None


def classify_prod_cluster(
    cluster_args: dict,
    config_service: Optional[ConfigurationService] = None,
) -> ClusterClassification:
    """Classify using type prefix and merged spark_version (Airflow routing)."""
    cluster_type = str(cluster_args.get("type") or "")
    custom = cluster_args.get("custom_configurations") or {}
    override_sv = str(custom.get("spark_version") or "")

    if is_airflow_emr_cluster_type(cluster_type):
        spark_version = override_sv
        if config_service is not None:
            try:
                _, merged = resolve_airflow_compute_mode(cluster_args, config_service)
                spark_version = str(merged.get("spark_version") or override_sv)
            except Exception:
                pass
        return ClusterClassification(
            is_emr=True,
            cluster_type=cluster_type,
            spark_version=spark_version,
        )

    if config_service is not None:
        try:
            use_emr, merged = resolve_airflow_compute_mode(cluster_args, config_service)
            return ClusterClassification(
                is_emr=use_emr,
                cluster_type=cluster_type,
                spark_version=str(merged.get("spark_version") or ""),
            )
        except Exception:
            pass

    # Fallback when preset merge is unavailable: honor override spark_version.
    return ClusterClassification(
        is_emr=is_airflow_emr_cluster(override_sv),
        cluster_type=cluster_type,
        spark_version=override_sv,
    )


def should_fail_introduction(
    *,
    is_new_dag: bool,
    head: ClusterClassification,
    base: Optional[ClusterClassification],
) -> bool:
    """True when HEAD introduces Databricks (new DAG or EMR→Databricks)."""
    if head.is_emr:
        return False
    if is_new_dag:
        return True
    if base is None:
        return True
    return base.is_emr


def dag_root_and_name(repo_relative: str) -> Optional[Tuple[str, str]]:
    parts = Path(repo_relative).parts
    if len(parts) < 3 or parts[0] != "dags":
        return None
    root = f"{parts[0]}/{parts[1]}/{parts[2]}"
    return root, parts[2]


def affected_dag_roots(changed_files: Dict[str, str]) -> List[Tuple[str, str]]:
    """DAG roots whose declaration or cluster file was added, modified, or deleted.

    Deletes matter for ``*_cluster.yml``: Airflow then falls back to any inline
    ``cluster`` on the declaration, which can introduce Databricks without an
    edit to ``*_declaration.yml``.
    """
    roots: Dict[str, str] = {}
    for path, status in changed_files.items():
        if status not in RELEVANT_STATUSES:
            continue
        parsed = dag_root_and_name(path)
        if parsed is None:
            continue
        root, dag_name = parsed
        basename = Path(path).name
        if basename in (
            f"{dag_name}_cluster.yml",
            f"{dag_name}_declaration.yml",
        ):
            roots[root] = dag_name
    return sorted(roots.items())


def read_text_from_git(git_ref: str, repo_relative: str) -> Optional[str]:
    result = subprocess.run(
        ["git", "show", f"{git_ref}:{repo_relative}"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    return result.stdout


def resolve_prod_cluster_from_texts(
    *,
    cluster_text: Optional[str],
    declaration_text: Optional[str],
) -> Optional[dict]:
    """Prefer ``*_cluster.yml`` over inline declaration ``cluster:``."""
    if cluster_text is not None:
        doc = parse_yaml_text(cluster_text)
        cluster = extract_prod_cluster(doc, from_cluster_file=True)
        if cluster is not None:
            return cluster
    if declaration_text is not None:
        doc = parse_yaml_text(declaration_text)
        return extract_prod_cluster(doc, from_cluster_file=False)
    return None


def resolve_prod_cluster_on_disk(dag_root: str, dag_name: str) -> Optional[dict]:
    cluster_path = REPO_ROOT / dag_root / f"{dag_name}_cluster.yml"
    decl_path = REPO_ROOT / dag_root / f"{dag_name}_declaration.yml"
    cluster_text = (
        cluster_path.read_text(encoding="utf-8") if cluster_path.is_file() else None
    )
    decl_text = decl_path.read_text(encoding="utf-8") if decl_path.is_file() else None
    return resolve_prod_cluster_from_texts(
        cluster_text=cluster_text, declaration_text=decl_text
    )


def resolve_prod_cluster_at_ref(
    git_ref: str, dag_root: str, dag_name: str
) -> Optional[dict]:
    cluster_rel = f"{dag_root}/{dag_name}_cluster.yml"
    decl_rel = f"{dag_root}/{dag_name}_declaration.yml"
    return resolve_prod_cluster_from_texts(
        cluster_text=read_text_from_git(git_ref, cluster_rel),
        declaration_text=read_text_from_git(git_ref, decl_rel),
    )


def evaluate_dag(
    dag_root: str,
    dag_name: str,
    changed_files: Dict[str, str],
    from_ref: str,
    config_service: ConfigurationService,
    dag_exceptions: Set[str],
    path_exceptions: Set[str],
) -> Optional[Violation]:
    if is_excepted(dag_name, dag_root, dag_exceptions, path_exceptions):
        return None

    head_cluster = resolve_prod_cluster_on_disk(dag_root, dag_name)
    if head_cluster is None:
        return None

    head = classify_prod_cluster(head_cluster, config_service)
    if head.is_emr:
        return None

    decl_rel = f"{dag_root}/{dag_name}_declaration.yml"
    is_new_dag = changed_files.get(decl_rel) == "A"

    base_cluster = resolve_prod_cluster_at_ref(from_ref, dag_root, dag_name)
    base = (
        classify_prod_cluster(base_cluster, config_service)
        if base_cluster is not None
        else None
    )

    if not should_fail_introduction(is_new_dag=is_new_dag, head=head, base=base):
        return None

    if is_new_dag:
        reason = "new DAG with Databricks production runtime"
    elif base is None:
        reason = "Databricks production runtime with no prior prod cluster on base"
    else:
        reason = (
            "production runtime changed from EMR to Databricks "
            f"(was type={base.cluster_type!r} spark_version={base.spark_version!r})"
        )

    return Violation(
        dag_root=dag_root,
        reason=reason,
        cluster_type=head.cluster_type,
        spark_version=head.spark_version,
    )


def collect_violations(branch: str) -> List[Violation]:
    os.environ.setdefault("ENVIRONMENT", "prod")
    ConfigurationService._instance_cache.clear()
    config_service = ConfigurationService()

    git_service = GitService()
    from_ref = resolve_diff_from_ref(branch)
    changed = git_service.get_modified_files_from_diff(from_ref, "HEAD")
    dag_exceptions, path_exceptions = load_exceptions()

    violations: List[Violation] = []
    for dag_root, dag_name in affected_dag_roots(changed):
        violation = evaluate_dag(
            dag_root,
            dag_name,
            changed,
            from_ref,
            config_service,
            dag_exceptions,
            path_exceptions,
        )
        if violation is not None:
            violations.append(violation)
    return violations


def audit_all_databricks() -> List[Tuple[str, ClusterClassification]]:
    os.environ.setdefault("ENVIRONMENT", "prod")
    ConfigurationService._instance_cache.clear()
    config_service = ConfigurationService()

    found: List[Tuple[str, ClusterClassification]] = []
    for decl in sorted(REPO_ROOT.glob("dags/*/*/*_declaration.yml")):
        dag_name = decl.name[: -len("_declaration.yml")]
        dag_root = str(decl.parent.relative_to(REPO_ROOT))
        if dag_root.count("/") != 2:
            continue
        cluster = resolve_prod_cluster_on_disk(dag_root, dag_name)
        if cluster is None:
            continue
        classification = classify_prod_cluster(cluster, config_service)
        if not classification.is_emr:
            found.append((dag_root, classification))
    return found


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Fail if a PR introduces Databricks production runtime "
            "(new DAG or EMR→Databricks)."
        )
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("-b", "--branch", help="Current branch (CI_COMMIT_BRANCH)")
    group.add_argument(
        "-a",
        "--all-files",
        action="store_true",
        help="List all DAGs with Databricks prod clusters (local audit, exit 0)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.all_files:
        found = audit_all_databricks()
        print(f"Found {len(found)} DAG(s) with Databricks production runtime:")
        for dag_root, c in found:
            print(
                f"  {dag_root}: type={c.cluster_type!r} "
                f"spark_version={c.spark_version!r}"
            )
        return 0

    violations = collect_violations(args.branch)
    if not violations:
        print("OK: No new Databricks production cluster introductions.")
        return 0

    print(
        f"\nFound {len(violations)} Databricks production runtime "
        "introduction(s) that are blocked:\n",
        file=sys.stderr,
    )
    for v in violations:
        print(
            f"  {v.dag_root}: {v.reason}\n"
            f"      type={v.cluster_type!r} spark_version={v.spark_version!r}",
            file=sys.stderr,
        )
    print(
        "\nUse an `emr_*` preset (or `custom_cluster` with "
        "`spark_version: emr-*`). To bypass, add the DAG to "
        "packages/bietlejuice-compiler/scripts/ci_cd/"
        "databricks_cluster_exceptions.yml "
        "(requires @quintoandar/data-ingestion-code-owners approval).",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
