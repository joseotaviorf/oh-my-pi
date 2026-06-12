"""Validate CLI and path inputs before they reach SQL execution."""

from __future__ import annotations

import re
from typing import Iterable

# DAG folder names, table names, domain folders (e.g. fintech, tech_platform).
SAFE_RESOURCE_NAME = re.compile(r"^[a-z][a-z0-9_]*$")

# Git refs used for baseline SQL (master, origin/main, commit shas, tags).
SAFE_GIT_REF = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9._/^~-]*$")

ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

SQL_IDENTIFIER = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*$")
SQL_ORDER_LITERAL = re.compile(r"^\d+$")


class InputValidationError(ValueError):
    """Raised when a user-supplied value is not safe to embed in SQL or paths."""


def validate_resource_name(value: str, field: str) -> str:
    if not SAFE_RESOURCE_NAME.fullmatch(value):
        raise InputValidationError(
            f"Invalid {field} {value!r}: expected lowercase snake_case identifier"
        )
    return value


def validate_git_ref(value: str) -> str:
    if not SAFE_GIT_REF.fullmatch(value):
        raise InputValidationError(f"Invalid git ref {value!r}")
    return value


def validate_iso_date(value: str, field: str) -> str:
    if not ISO_DATE.fullmatch(value):
        raise InputValidationError(
            f"Invalid {field} {value!r}: expected YYYY-MM-DD"
        )
    return value


def validate_order_by_column(column: str) -> str:
    if SQL_ORDER_LITERAL.fullmatch(column) or SQL_IDENTIFIER.fullmatch(column):
        return column
    raise InputValidationError(f"Invalid ORDER BY column {column!r}")


def format_order_by_clause(order_by_cols: Iterable[str]) -> str:
    return ", ".join(validate_order_by_column(col) for col in order_by_cols)


def validate_sample_limit(limit: int) -> int:
    if limit < 1 or limit > 10_000:
        raise InputValidationError(f"Invalid sample limit {limit!r}")
    return limit


def validate_cli_args(
    *,
    dag: str,
    domain: str,
    table: str | None = None,
    git_ref: str | None = None,
) -> None:
    validate_resource_name(dag, "dag")
    validate_resource_name(domain, "domain")
    if table is not None:
        validate_resource_name(table, "table")
    if git_ref is not None:
        validate_git_ref(git_ref)
