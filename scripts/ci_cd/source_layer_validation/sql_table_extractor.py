# -*- coding: utf-8 -*-
"""
Extract metastore-style table references (schema.table) from SQL text.

Uses sqlglot (Spark dialect) for AST-based discovery. Used by
``dag_reference_extractors`` when the active profile sets ``sql_scan_globs``
(e.g. default ``dags`` profile); Spark-only profiles may omit SQL scanning.

Limitations:
- Heavy Jinja/bracket templating may require extending normalize_sql_for_table_extraction.
- Single-name FROM clauses (CTEs without schema) are skipped; inner CTE bodies are still walked.
"""

from __future__ import print_function

import re
from pathlib import Path
from typing import List, Optional, Set

from sqlglot import exp, parse_one

from scripts.ci_cd.source_layer_validation.layer_classifier import parse_table_fqn


def normalize_sql_for_table_extraction(sql: str) -> str:
    """
    Strip comments and replace common templates so sqlglot can parse.

    Keep this aligned with governance SQL normalization only where needed; avoid
    importing validate_lineage_consistency to limit coupling.
    """
    sql = re.sub(r"--.*?$", "", sql, flags=re.MULTILINE)
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.DOTALL)
    # Jinja-style {{ var }} (not numeric {{2}})
    sql = re.sub(r"\{\{(\d+)\}\}", r"{\1}", sql)
    sql = re.sub(
        r"\{\{\s*[a-zA-Z_][a-zA-Z0-9_\s]*\s*\}\}",
        "'DUMMY'",
        sql,
    )
    # Bracket params like {load_start_date}
    sql = re.sub(r"\{[a-zA-Z_][a-zA-Z0-9_]*\}", "'DUMMY'", sql)
    return sql


def _table_node_to_fqn(table: exp.Table) -> Optional[str]:
    """
    Build schema.table for layer classification.

    Ignores catalog (first segment) so ``hive.dw_rent.fact`` -> ``dw_rent.fact``.
    Skips bare names (likely CTE/subquery aliases).
    """
    name = table.name
    if not name:
        return None
    name = name.replace("`", "").strip('"')

    db = table.db
    if not db:
        return None
    db = db.replace("`", "").strip('"')

    fqn = "{}.{}".format(db, name)
    if parse_table_fqn(fqn):
        return fqn
    return None


def extract_table_fqns_from_sql_text(sql: str, dialect: str = "spark") -> Set[str]:
    """
    Parse SQL and return unique schema.table strings from all Table nodes.
    """
    out = set()
    if not sql or not sql.strip():
        return out
    normalized = normalize_sql_for_table_extraction(sql)
    try:
        parsed = parse_one(normalized, read=dialect)
    except Exception:
        return out
    if parsed is None:
        return out
    for table in parsed.find_all(exp.Table):
        fqn = _table_node_to_fqn(table)
        if fqn:
            out.add(fqn)
    return out


def extract_table_fqns_from_sql_file_path(
    path: Path, dialect: str = "spark"
) -> Set[str]:
    """
    Parse a single SQL file and return schema.table references.
    """
    path = Path(path)
    if not path.is_file():
        return set()
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return set()
    return extract_table_fqns_from_sql_text(text, dialect=dialect)


def extract_table_fqns_from_sql_files(
    dag_root: Path, relative_globs: List[str], dialect: str = "spark"
) -> Set[str]:
    """
    For each glob pattern relative to dag_root, read matching .sql files and
    union table FQNs. Patterns use pathlib semantics (``**`` supported on Py3.5+).

    Args:
        dag_root: DAG folder (e.g. dags/for_rent/dw_contract).
        relative_globs: e.g. ["queries/dw/*.sql", "queries/**/*.sql"].
        dialect: sqlglot read dialect (default spark).
    """
    root = Path(dag_root)
    tables = set()
    for pattern in relative_globs or []:
        for path in root.glob(pattern):
            if not path.is_file():
                continue
            if path.suffix.lower() != ".sql":
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except OSError:
                continue
            tables |= extract_table_fqns_from_sql_text(text, dialect=dialect)
    return tables
