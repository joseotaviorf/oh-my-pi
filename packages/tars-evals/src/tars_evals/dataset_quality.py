"""Exclude scaffolding titles and non-runnable SQL from generated datasets."""

from __future__ import annotations

import re

# Titles that denote doc scaffolding, not user-facing /tars questions.
_SCAFFOLDING_TITLE_RE = re.compile(
    r"(?i)^(?:"
    r"base\s+cte(?:\s*\(.*\))?"
    r"|full\s+reference\s+query"
    r"|golden\s+quer(?:y|ies)"
    r"|reference\s+query"
    r"|shared\s+(?:base|cte)"
    r"|common\s+(?:base|cte)"
    r"|helper\s+cte"
    r"|(?:zendesk|salesforce|unified)\s+(?:backlog\s+)?canonical\s+base"
    r"|unified\s+backlog\s+base"
    r")(?:\s|$|[:(])"
)

_CHARGEHUB_PARTIAL_TITLE_RE = re.compile(r"(?i)same\s+query.*chargehub")

# SQL comments / stubs that point at other goldens instead of answering standalone.
_SEE_QUERY_RE = re.compile(r"see\s+query\s+\d+", re.I)
_USES_BASE_CTE_RE = re.compile(r"uses\s+base\s+cte", re.I)
_PREPEND_FROM_QUERY_RE = re.compile(r"prepend.*from\s+query\s+\d+", re.I)

# Non-literal golden SQL (curly or angle-bracket placeholders). Case-insensitive
# so uppercase tokens like <YYYYMM>, <YEAR>, <VERSION> are caught too.
_PLACEHOLDER_RE = re.compile(r"\{[a-z_]+\}|<[a-z_][a-z0-9_]*>", re.I)

# Fragments that reference CTEs defined only in sibling doc queries.
_EXTERNAL_CTE_REF_RE = re.compile(
    r"\bFROM\s+("
    r"unified_backlog_base"
    r"|zendesk_canonical_base"
    r"|salesforce_canonical_base"
    r"|actual_vol"
    r"|tb_fl"
    r")\b",
    re.I,
)


def _strip_sql_comments(sql: str) -> str:
    without_line = re.sub(r"--[^\n]*", "", sql)
    return re.sub(r"/\*.*?\*/", "", without_line, flags=re.S)


def is_with_only_sql(sql: str) -> bool:
    """True when SQL is only CTE definitions (no top-level SELECT)."""
    stripped = _strip_sql_comments(sql).strip().rstrip(";")
    if not stripped.upper().startswith("WITH"):
        return False
    depth = 0
    i = 0
    while i < len(stripped):
        char = stripped[i]
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        elif depth == 0 and stripped[i : i + 6].upper() == "SELECT":
            return False
        i += 1
    return True


def is_sql_fragment(sql: str) -> bool:
    """True for non-runnable SQL: a bare expression/column stub with no
    top-level SELECT at all, or a multi-part SELECT stub without a FROM
    clause."""
    stripped = _strip_sql_comments(sql).strip().rstrip(";")
    if not stripped:
        # Comment-only "stub" — nothing executable survives comment-stripping.
        return True
    upper = stripped.upper()
    if "SELECT" not in upper:
        # e.g. a bare `DATE_TRUNC(...) AS cohort_period` column snippet
        # documenting a variant — never valid standalone SQL.
        return True
    if "FROM" in upper or not upper.startswith("SELECT"):
        return False
    # Trivial literal selects (common in tests/smoke goldens) are still runnable.
    if re.fullmatch(r"SELECT\s+\d+\s*", upper):
        return False
    # Multi-line or multi-column SELECT without FROM is a doc fragment.
    return "\n" in stripped or len(stripped.split()) > 3


def exclusion_reason(*, question: str, expected_query: str) -> str | None:
    """Return a short reason when an item should be excluded from eval datasets."""
    sql = expected_query.strip()
    if not sql:
        return "empty_sql"

    if _SCAFFOLDING_TITLE_RE.search(question):
        return "scaffolding_title"
    if _CHARGEHUB_PARTIAL_TITLE_RE.search(question):
        return "chargehub_partial_title"
    if _SEE_QUERY_RE.search(sql):
        return "see_query_ref"
    if _USES_BASE_CTE_RE.search(sql):
        return "uses_base_cte"
    if _PREPEND_FROM_QUERY_RE.search(sql):
        return "prepend_from_query"
    if _EXTERNAL_CTE_REF_RE.search(sql):
        return "external_cte_ref"
    if is_with_only_sql(sql):
        return "with_only_sql"
    if _PLACEHOLDER_RE.search(sql):
        return "unreplaced_placeholder"
    if is_sql_fragment(sql):
        return "sql_fragment"
    return None
