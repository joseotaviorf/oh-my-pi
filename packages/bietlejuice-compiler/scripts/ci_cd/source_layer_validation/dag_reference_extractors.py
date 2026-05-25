"""
Discover metastore table references (schema.table) under a DAG folder.

Sources: SQL files (via profile globs), Spark job YAML confs (e.g. prod/forno),
and string-literal ``spark.table("schema.table")`` in Python under ``spark_jobs/``.
"""

import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

import yaml

from scripts.ci_cd.source_layer_validation.layer_classifier import parse_table_fqn
from scripts.ci_cd.source_layer_validation.sql_table_extractor import (
    extract_table_fqns_from_sql_file_path,
)

# spark.table("schema.table") or spark.table('schema.table')
SPARK_TABLE_LITERAL_RE = re.compile(
    r"""spark\.table\s*\(\s*["']([a-zA-Z][a-zA-Z0-9_]*\.[a-zA-Z][a-zA-Z0-9_]*)["']\s*\)"""
)


def _collect_yaml_strings(obj: Any, skip_keys: Set[str], out: Set[str]) -> None:
    if isinstance(obj, dict):
        for key, val in obj.items():
            if key in skip_keys:
                continue
            _collect_yaml_strings(val, skip_keys, out)
    elif isinstance(obj, list):
        for item in obj:
            _collect_yaml_strings(item, skip_keys, out)
    elif isinstance(obj, str):
        parsed = parse_table_fqn(obj)
        if parsed:
            schema, table = parsed
            out.add(f"{schema}.{table}")


def extract_tables_from_spark_confs(
    dag_root: Path,
    yaml_conf_files: List[str],
    spark_jobs_subdir: str,
    skip_yaml_keys: Optional[List[str]],
) -> Set[str]:
    """
    Load prod_conf.yml / forno_conf.yml (or configured names) and collect schema.table strings.
    """
    tables = set()
    skip = set(skip_yaml_keys or [])
    sub = dag_root / spark_jobs_subdir
    if not sub.is_dir():
        return tables

    for name in yaml_conf_files:
        path = sub / name
        if not path.is_file():
            continue
        with open(path) as f:
            data = yaml.safe_load(f)
        if data is None:
            continue
        _collect_yaml_strings(data, skip, tables)
    return tables


def extract_tables_from_python_literals(
    dag_root: Path, spark_jobs_subdir: str, python_globs: List[str]
) -> Set[str]:
    tables = set()
    sub = dag_root / spark_jobs_subdir
    if not sub.is_dir():
        return tables

    for pattern in python_globs:
        for path in sub.glob(pattern):
            if not path.is_file():
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except OSError:
                continue
            for m in SPARK_TABLE_LITERAL_RE.finditer(text):
                tables.add(m.group(1))
    return tables


def _skip_workflow_types_set(profile: Dict[str, Any]) -> Set[str]:
    return {x.lower() for x in (profile.get("skip_workflow_types") or []) if x}


def _normalize_repo_rel_path(path_str: str) -> str:
    return path_str.replace("\\", "/")


def _repo_relative_path_for_output(file_path: Path) -> str:
    """Repo-relative path using forward slashes (matches git / DAG roots)."""
    cwd = Path.cwd().resolve()
    try:
        return _normalize_repo_rel_path(str(file_path.resolve().relative_to(cwd)))
    except ValueError:
        return _normalize_repo_rel_path(str(file_path.resolve()))


def extract_tables_by_source_file(
    profile: Dict[str, Any], dag_root_path: Path, workflow_type: Optional[str]
) -> Dict[str, Set[str]]:
    """
    Map repo-relative file path -> set of schema.table references for that file only.

    Same sources and skip rules as ``extract_all_tables_for_dag``.
    """
    wtype = (workflow_type or "").lower()
    if wtype and wtype in _skip_workflow_types_set(profile):
        return {}

    root = Path(dag_root_path).resolve()
    out: Dict[str, Set[str]] = {}

    def add_for_path(abs_path: Path, table_set: Set[str]) -> None:
        if not table_set:
            return
        key = _repo_relative_path_for_output(abs_path)
        if key not in out:
            out[key] = set()
        out[key].update(table_set)

    sql_globs = profile.get("sql_scan_globs") or []
    dialect = profile.get("sql_read_dialect", "spark")
    for pattern in sql_globs or []:
        for path in root.glob(pattern):
            if not path.is_file() or path.suffix.lower() != ".sql":
                continue
            add_for_path(
                path, extract_table_fqns_from_sql_file_path(path, dialect=dialect)
            )

    spark_sub = profile.get("spark_jobs_subdir", "spark_jobs")
    sub = root / spark_sub
    skip = set(profile.get("skip_yaml_keys", []))
    if sub.is_dir():
        for name in profile.get("yaml_conf_files", []):
            path = sub / name
            if not path.is_file():
                continue
            with open(path, encoding="utf-8") as f:
                data = yaml.safe_load(f)
            if data is None:
                continue
            tables = set()
            _collect_yaml_strings(data, skip, tables)
            add_for_path(path, tables)

        if profile.get("scan_python_spark_table_literals"):
            for pattern in profile.get("python_globs", ["load_*.py"]):
                for path in sub.glob(pattern):
                    if not path.is_file() or path.suffix.lower() != ".py":
                        continue
                    try:
                        text = path.read_text(encoding="utf-8")
                    except OSError:
                        continue
                    tables = set()
                    for m in SPARK_TABLE_LITERAL_RE.finditer(text):
                        tables.add(m.group(1))
                    add_for_path(path, tables)

    return out


def extract_all_tables_for_core_dag(
    profile: Dict[str, Any], dag_root_path: Path
) -> Set[str]:
    """
    Union of YAML conf refs, optional Python literal spark.table refs, and
    optional SQL files (when profile sets ``sql_scan_globs``).

    Kept for unit tests and callers that need extraction without ``workflow_type``
    / skip_workflow_types branching (e.g. legacy ``core`` profile layouts without
    ``sql_scan_globs`` = YAML/Python only).
    """
    root = Path(dag_root_path)
    by_file = extract_tables_by_source_file(profile, root, None)
    if not by_file:
        return set()
    return set().union(*by_file.values())


def extract_all_tables_for_dag(
    profile: Dict[str, Any], dag_root_path: Path, workflow_type: Optional[str]
) -> Set[str]:
    """
    Discover referenced tables for a DAG folder using profile rules.

    Skips extraction entirely when ``workflow_type`` is listed under
    ``skip_workflow_types`` in the profile (CDC, pulls, etc.).

    SQL: ``sql_scan_globs`` relative to dag root. Spark YAML: ``yaml_conf_files``
    under ``spark_jobs_subdir``. Python ``spark.table`` literals when
    ``scan_python_spark_table_literals`` is true.
    """
    wtype = (workflow_type or "").lower()
    if wtype and wtype in _skip_workflow_types_set(profile):
        return set()

    root = Path(dag_root_path)
    by_file = extract_tables_by_source_file(profile, root, workflow_type)
    if not by_file:
        return set()
    return set().union(*by_file.values())


def extract_tables_for_strict_repo_paths(
    profile: Dict[str, Any],
    dag_root_path: Path,
    repo_relative_paths: List[str],
    workflow_type: Optional[str],
) -> Set[str]:
    """
    Tables referenced only from the given repo-relative file paths (new ``A`` files).
    Paths must live under ``dag_root_path``.
    """
    by_file = extract_tables_by_source_file(profile, dag_root_path, workflow_type)
    wanted = {_normalize_repo_rel_path(p) for p in repo_relative_paths}
    tables = set()
    for rel_key, tset in by_file.items():
        if rel_key in wanted:
            tables |= tset
    return tables
