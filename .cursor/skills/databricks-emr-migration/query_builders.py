"""Build Databricks validation queries from repo-pinned SQL.

``pinned_sql`` must originate from ``load_pinned_sql()`` (git-controlled DAG
query files with validated path components and ISO load dates). ORDER BY columns
must be validated identifiers from schema/declaration resolution.
"""

from __future__ import annotations

from input_validation import format_order_by_clause, validate_sample_limit
from models import SchemaEntry, TableProfile
from profile import build_profile_query


def build_describe_query(pinned_sql: str) -> str:
    return f"DESCRIBE ({pinned_sql})"


def build_count_query(pinned_sql: str) -> str:
    return f"SELECT COUNT(*) AS cnt FROM ({pinned_sql}) AS t"


def build_profile_query_for_schema(
    pinned_sql: str,
    schema: list[SchemaEntry],
    *,
    checksum_skipped: set[str] | None = None,
) -> tuple[str, TableProfile]:
    return build_profile_query(
        pinned_sql,
        schema,
        checksum_skipped=checksum_skipped,
    )


def build_sample_query(
    pinned_sql: str,
    order_by_cols: list[str],
    sample_limit: int,
) -> str:
    limit = validate_sample_limit(sample_limit)
    order_clause = format_order_by_clause(order_by_cols)
    return (
        f"SELECT * FROM ({pinned_sql}) AS t ORDER BY {order_clause} "
        f"LIMIT {limit}"
    )
