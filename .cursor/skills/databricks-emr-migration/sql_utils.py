"""SQL loading, date injection, and time-function pinning."""

from __future__ import annotations

import hashlib
import re
import subprocess
from pathlib import Path
from typing import Optional

from declaration import is_cdc_clean_workflow
from input_validation import (
    validate_git_ref,
    validate_iso_date,
    validate_resource_name,
)

# Mirrors load_cdc_clean runtime injection and lineage CDC_CLEAN_INJECTED_COLUMNS.
CDC_CLEAN_COLUMNS = ("op_cdc", "ts_cdc_transaction", "ts_database_transaction")

NON_COMPARABLE_COLUMNS = frozenset(
    {
        "ts_load",
        "op_cdc",
        "ts_cdc_transaction",
        "ts_database_transaction",
    }
)

_FROM_SCHEMA_TABLE_RE = re.compile(
    r"(FROM\s+`?\w+\`?\.`?\w+`?)",
    re.IGNORECASE,
)


def pin_sql(
    sql: str,
    load_start_date: str,
    load_end_date: str,
) -> str:
    """Inject load dates and pin non-deterministic time functions."""
    validate_iso_date(load_start_date, "load_start_date")
    validate_iso_date(load_end_date, "load_end_date")
    pinned = sql.replace("{load_start_date}", load_start_date)
    pinned = pinned.replace("{load_end_date}", load_end_date)
    # Mirror production query.format(): {{ }} in file → single braces in executed SQL.
    pinned = pinned.replace("{{", "{").replace("}}", "}")
    ts_literal = f"TIMESTAMP '{load_start_date} 00:00:00'"
    current_date_literal = f"DATE '{load_end_date}'"
    pinned = re.sub(
        r"\bCURRENT_TIMESTAMP\s*\(\s*\)",
        ts_literal,
        pinned,
        flags=re.IGNORECASE,
    )
    pinned = re.sub(r"\bNOW\s*\(\s*\)", ts_literal, pinned, flags=re.IGNORECASE)
    pinned = re.sub(
        r"\bCURRENT_DATE\s*\(\s*\)",
        current_date_literal,
        pinned,
        flags=re.IGNORECASE,
    )
    pinned = re.sub(
        r"\bCURRENT_DATE\b(?!\s*\()",
        current_date_literal,
        pinned,
        flags=re.IGNORECASE,
    )
    return pinned


def apply_cdc_clean_injection(
    query: str,
    columns: tuple[str, ...] = CDC_CLEAN_COLUMNS,
) -> str:
    """Mirror ``load_cdc_clean.insert_columns_into_query`` for migration validate."""
    split_values_in_from = _FROM_SCHEMA_TABLE_RE.split(query)
    split_values_in_from[-3] += "".join(f",{column}\n" for column in columns)
    return "".join(split_values_in_from)


def sql_hash(sql: str) -> str:
    return hashlib.sha256(sql.encode("utf-8")).hexdigest()


def read_sql_from_disk(sql_path: Path) -> str:
    return sql_path.read_text(encoding="utf-8")


def read_sql_from_git(
    domain: str,
    dag_name: str,
    layer: str,
    table_name: str,
    git_ref: str,
    repo_root: Optional[Path] = None,
) -> str:
    """Read SQL file contents from a git ref (e.g. master for pre-rewrite baseline)."""
    validate_resource_name(domain, "domain")
    validate_resource_name(dag_name, "dag")
    validate_resource_name(layer, "layer")
    validate_resource_name(table_name, "table")
    validate_git_ref(git_ref)
    root = repo_root or Path.cwd()
    rel_path = f"dags/{domain}/{dag_name}/queries/{layer}/{table_name}.sql"
    result = subprocess.run(
        ["git", "show", f"{git_ref}:{rel_path}"],
        capture_output=True,
        text=True,
        cwd=str(root),
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Failed to read {rel_path} from git ref {git_ref}: {result.stderr.strip()}"
        )
    return result.stdout


def load_pinned_sql(
    domain: str,
    dag_name: str,
    layer: str,
    table_name: str,
    load_start_date: str,
    load_end_date: str,
    git_ref: Optional[str] = None,
    repo_root: Optional[Path] = None,
) -> str:
    validate_resource_name(domain, "domain")
    validate_resource_name(dag_name, "dag")
    validate_resource_name(layer, "layer")
    validate_resource_name(table_name, "table")
    if git_ref:
        sql = read_sql_from_git(domain, dag_name, layer, table_name, git_ref, repo_root)
    else:
        root = repo_root or Path.cwd()
        sql_path = root / "dags" / domain / dag_name / "queries" / layer / f"{table_name}.sql"
        sql = read_sql_from_disk(sql_path)
    pinned = pin_sql(sql, load_start_date, load_end_date)
    if is_cdc_clean_workflow(domain, dag_name, layer, repo_root):
        pinned = apply_cdc_clean_injection(pinned)
    return pinned


def detect_non_comparable_cols(schema_cols: list[str]) -> list[str]:
    return [name for name in schema_cols if name.lower() in NON_COMPARABLE_COLUMNS]
