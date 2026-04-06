# -*- coding: utf-8 -*-
"""
Classify paths under a DAG folder for strict-mode (new file) validation.
"""

from pathlib import Path
from typing import List


def _norm_dag_root_prefix(dag_root: str) -> str:
    return dag_root.rstrip("/") + "/"


def is_source_artifact_rel_path(rel_path: str) -> bool:
    """
    True if a file under the DAG root is a source artifact for layer policy
    (SQL, Spark job conf, Spark/Python job code).
    """
    if not rel_path:
        return False
    p = Path(rel_path)
    parts = p.parts
    if not parts:
        return False
    # query_delta / SQL DAGs
    if parts[0] == "queries" and p.suffix.lower() == ".sql":
        return True
    if parts[0] == "spark_jobs":
        suf = p.suffix.lower()
        if suf in (".sql", ".yml", ".yaml", ".py"):
            return True
    return False


def list_added_source_artifacts(
    dag_root: str, changed_files: dict, added_status: str = "A"
) -> List[str]:
    """
    Repo-relative paths that are new (``A``) source artifacts under dag_root.
    """
    prefix = _norm_dag_root_prefix(dag_root)
    out: List[str] = []
    for path, status in changed_files.items():
        if status != added_status:
            continue
        if not path.startswith(prefix):
            continue
        rel = path[len(prefix) :]
        if is_source_artifact_rel_path(rel):
            out.append(path)
    return sorted(out)


def dag_has_new_declaration(dag_root: str, changed_files: dict) -> bool:
    """True if this DAG's ``*_declaration.yml`` is newly added in the diff."""
    name = Path(dag_root).name
    decl = "{}/{}_declaration.yml".format(dag_root.rstrip("/"), name)
    return changed_files.get(decl) == "A"


def dag_requires_strict_validation(dag_root: str, changed_files: dict) -> bool:
    """
    Strict CI failure path: new DAG (new declaration) or any new source artifact.
    """
    if dag_has_new_declaration(dag_root, changed_files):
        return True
    return bool(list_added_source_artifacts(dag_root, changed_files))
