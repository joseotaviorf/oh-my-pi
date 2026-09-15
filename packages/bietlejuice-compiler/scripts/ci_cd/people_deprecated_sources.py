"""Deprecated upstream schemas for People SQL — pattern definitions and exempt DAGs.

Legacy DAG folders may still read deprecated sources while they are phased out.
New development under domain-focused DAGs must not reference these schemas.

See ``people_domain.mdc`` § "Deprecated Sources — Do Not Use in New Development".
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Pattern, Tuple

from scripts.ci_cd.people_domain_scope import (
    dag_folder_from_path,
    domain_folder_from_parts,
    normalize_path,
)

# DAG folder names under dags/people/ that may still reference deprecated sources.
LEGACY_DAG_EXEMPT_FOLDERS = frozenset(
    {
        "dw_employee",
        "hr_system",
        "enrich_hr_system",
        "enrich_hr_system_custom",
        "enrich_pin",
        "enrich_employment",
    }
)


@dataclass(frozen=True)
class DeprecatedSourcePattern:
    """A deprecated SQL reference pattern with a stable CI label and remediation hint."""

    label: str
    pattern: Pattern[str]
    hint: str


DEPRECATED_SOURCE_PATTERNS: Tuple[DeprecatedSourcePattern, ...] = (
    DeprecatedSourcePattern(
        label="datalake_hr_system",
        pattern=re.compile(
            r"\bdatalake_hr_system(?:_(?:raw|clean))?\.",
            re.IGNORECASE,
        ),
        hint="use pin_* clean tables or datalake_people enrich outputs",
    ),
    DeprecatedSourcePattern(
        label="datalake_employment",
        pattern=re.compile(r"\bdatalake_employment\.", re.IGNORECASE),
        hint="use datalake_people.identifier_mapping and pin_* sources",
    ),
    DeprecatedSourcePattern(
        label="greenhouse_v1",
        pattern=re.compile(
            r"\bdatalake_greenhouse(?:_(?:raw|clean))?\.",
            re.IGNORECASE,
        ),
        hint="use greenhouse_v3 or greenhouse_audit_log",
    ),
    DeprecatedSourcePattern(
        label="datalake_pin_enrich",
        pattern=re.compile(r"\bdatalake_pin\.", re.IGNORECASE),
        hint="use datalake_people or pin_* clean tables instead of enrich_pin outputs",
    ),
    DeprecatedSourcePattern(
        label="datalake_people_analytics_sandbox",
        pattern=re.compile(
            r"\bdatalake_people_analytics_sandbox\.",
            re.IGNORECASE,
        ),
        hint="use pin_* clean, datalake_people, dw_*, or metric_* tables — sandbox CTAS are not governed",
    ),
)

_LINE_COMMENT_RE = re.compile(r"--.*$", re.MULTILINE)
_BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)


def _strip_block_comments_preserving_lines(sql: str) -> str:
    """Remove block comments while keeping newline count for accurate line numbers."""

    def _replace(match: re.Match[str]) -> str:
        return "\n" * match.group(0).count("\n")

    return _BLOCK_COMMENT_RE.sub(_replace, sql)


def _strip_line_comment(line: str) -> str:
    """Remove a trailing ``--`` comment from a single SQL line."""
    return _LINE_COMMENT_RE.sub("", line)


def people_dag_folder(path: Path | str) -> Optional[str]:
    """Return the DAG folder name under a scoped domain (e.g. ``pin``, ``dw_employee``)."""
    return dag_folder_from_path(path)


def is_legacy_dag_exempt(path: Path | str) -> bool:
    """Return True when a ``dags/people/`` legacy DAG may still cite deprecated schemas.

    Exemptions apply only under ``dags/people/`` while monolithic pipelines are
    migrated; ``enterprise_efficiency`` and new domain DAGs are never exempt.
    """
    normalized = normalize_path(str(path))
    if domain_folder_from_parts(normalized.split("/")) != "people":
        return False
    folder = dag_folder_from_path(path)
    return folder is not None and folder in LEGACY_DAG_EXEMPT_FOLDERS


def _strip_sql_comments(sql: str) -> str:
    """Remove line and block comments before scanning for schema references."""
    sql = _strip_block_comments_preserving_lines(sql)
    lines = [_strip_line_comment(line) for line in sql.splitlines()]
    return "\n".join(lines)


def find_deprecated_source_hits(sql: str) -> List[Tuple[str, int, str]]:
    """Scan SQL text for deprecated schema references after stripping comments.

    Returns ``(label, line_no, matched_line)`` tuples. Used to block new coupling
    to schemas that People is actively retiring (hr_system monolith, v1 Greenhouse).
    """
    stripped = _strip_sql_comments(sql)
    lines = stripped.splitlines()
    source_lines = sql.splitlines()
    hits: List[Tuple[str, int, str]] = []
    for line_no, line in enumerate(lines, start=1):
        for entry in DEPRECATED_SOURCE_PATTERNS:
            if entry.pattern.search(line):
                original = (
                    source_lines[line_no - 1].strip()
                    if line_no <= len(source_lines)
                    else line.strip()
                )
                hits.append((entry.label, line_no, original))
                break
    return hits


def hint_for_label(label: str) -> str:
    """Return the remediation hint for a deprecated-source label shown in CI output."""
    for entry in DEPRECATED_SOURCE_PATTERNS:
        if entry.label == label:
            return entry.hint
    return "see people_domain.mdc deprecated sources"
