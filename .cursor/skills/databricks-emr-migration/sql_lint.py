"""Detect SQL files that need EMR translation (Databricks-only constructs on master)."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path
from typing import List, Optional, Set, Tuple

from baseline import discover_tables
from paths import REPO_ROOT

# Critical patterns from databricks-emr-sql-lint/SKILL.md (Step 1)
CRITICAL_PATTERN = re.compile(
    r"\bQUALIFY\b"
    r"|\bGROUP BY ALL\b"
    r"|\bIFF\s*\("
    r"|\bDECODE\s*\("
    r"|\bDATEDIFF\s*\(\s*['\"]?(YEAR|QUARTER|MONTH|WEEK|DAY|HOUR|MINUTE|SECOND|MILLISECOND|MICROSECOND)\b"
    r"|[a-zA-Z_][a-zA-Z0-9_]*:\[?[\"']?[a-zA-Z_]"
    r"|::(ARRAY|BIGINT|BOOLEAN|DATE|DOUBLE|FLOAT|INT|INTEGER|LONG|MAP|SHORT|STRING|STRUCT|TIMESTAMP|TINYINT|VARIANT|DECIMAL)"
    r"|\*\s+EXCEPT\s*\("
    r"|\bWITH\s+RECURSIVE\b",
    re.IGNORECASE,
)


def lint_sql(sql: str) -> List[str]:
    """Return line snippets for each critical lint match."""
    findings: List[str] = []
    for line_no, line in enumerate(sql.splitlines(), start=1):
        if CRITICAL_PATTERN.search(line):
            findings.append(f"L{line_no}: {line.strip()[:120]}")
    return findings


def read_sql_from_git(
    domain: str,
    dag_name: str,
    layer: str,
    table_name: str,
    git_ref: str,
    repo_root: Optional[Path] = None,
) -> str:
    """Read SQL from git ref, falling back to the working tree for branch-only files."""
    root = repo_root or REPO_ROOT
    rel_path = f"dags/{domain}/{dag_name}/queries/{layer}/{table_name}.sql"
    disk_path = root / rel_path
    result = subprocess.run(
        ["git", "show", f"{git_ref}:{rel_path}"],
        capture_output=True,
        text=True,
        cwd=str(root),
    )
    if result.returncode == 0:
        return result.stdout

    if disk_path.is_file():
        return disk_path.read_text(encoding="utf-8")

    raise RuntimeError(
        f"Failed to read {rel_path} from git ref {git_ref}: {result.stderr.strip()}"
    )


def table_needs_translation(
    domain: str,
    dag_name: str,
    layer: str,
    table_name: str,
    git_ref: str = "master",
    repo_root: Optional[Path] = None,
) -> bool:
    sql = read_sql_from_git(domain, dag_name, layer, table_name, git_ref, repo_root)
    return bool(lint_sql(sql))


def discover_tables_needing_translation(
    domain: str,
    dag_name: str,
    git_ref: str = "master",
    table_filter: Optional[str] = None,
    repo_root: Optional[Path] = None,
) -> Tuple[List[Tuple[str, str]], List[Tuple[str, str]]]:
    """Return (translated, skipped) table lists as (table_name, layer) tuples."""
    translated: List[Tuple[str, str]] = []
    skipped: List[Tuple[str, str]] = []
    for table_name, layer in discover_tables(
        domain, dag_name, table_filter, repo_root=repo_root
    ):
        if table_needs_translation(domain, dag_name, layer, table_name, git_ref, repo_root):
            translated.append((table_name, layer))
        else:
            skipped.append((table_name, layer))
    return translated, skipped


def translated_table_names(
    domain: str,
    dag_name: str,
    git_ref: str = "master",
    table_filter: Optional[str] = None,
    repo_root: Optional[Path] = None,
) -> Set[str]:
    tables, _skipped = discover_tables_needing_translation(
        domain, dag_name, git_ref, table_filter, repo_root
    )
    return {table_name for table_name, _layer in tables}
