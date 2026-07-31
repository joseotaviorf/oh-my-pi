"""Shared golden-query SQL parsing and schema validation helpers.

Placeholder tokens common in entity docs (``{start_date}``, ``{load_start_date}``, …)
are substituted with fixed smoke-test literals before parsing.

Golden-query validation runs a **Trino syntax** gate (sqlglot ``dialect="trino"`` plus
structural ``()[]`` balance checks) before metadata table/column checks.
"""

from __future__ import annotations

import re
from typing import Any, Optional, Protocol

try:
    import sqlglot
    from sqlglot import exp
except ImportError:  # pragma: no cover - CI installs sqlglot via bietlejuice-compiler
    sqlglot = None  # type: ignore[assignment]
    exp = None  # type: ignore[assignment]

# Substitute template placeholders so sqlglot can parse the statement.
_PLACEHOLDER_SUBSTITUTIONS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\{load_start_date\}", re.I), "DATE '2024-01-01'"),
    (re.compile(r"\{load_end_date\}", re.I), "DATE '2024-12-31'"),
    (re.compile(r"\{start_date\}", re.I), "2024-01-01"),
    (re.compile(r"\{end_date\}", re.I), "'2024-12-31'"),
    (re.compile(r"\{dt_start\}", re.I), "2024-01-01"),
    (re.compile(r"\{dt_end\}", re.I), "2024-12-31"),
    (re.compile(r"\{start_year\}", re.I), "2024"),
    (re.compile(r"\{end_year\}", re.I), "2024"),
    (re.compile(r"\{window_start\}", re.I), "TIMESTAMP '2024-01-01 00:00:00'"),
    (re.compile(r"\{window_end\}", re.I), "TIMESTAMP '2024-12-31 23:59:59'"),
    (re.compile(r"\{day_\}", re.I), "2024-01-01"),
    (re.compile(r"DATE\s+'\{[^}]+\}'", re.I), "DATE '2024-01-01'"),
    (re.compile(r"TIMESTAMP\s+'\{[^}]+\}'", re.I), "TIMESTAMP '2024-01-01 00:00:00'"),
]

_SQL_TABLE_REF_RE = re.compile(
    r"\b(?:FROM|JOIN)\s+(?:hive\.)?([a-z][a-z0-9_]*)\.([a-z][a-z0-9_]*)",
    re.IGNORECASE,
)

_SKIPPED_METADATA_COLUMNS = frozenset({"_placeholder"})
_HIVE_CATALOG_PREFIX = "hive"
_TRINO_DIALECT = "trino"


def substitute_sql_placeholders(sql: str) -> str:
    out = sql
    for pattern, replacement in _PLACEHOLDER_SUBSTITUTIONS:
        out = pattern.sub(replacement, out)
    # Any remaining ``{token}`` braces would break the parser — neutralize generically.
    out = re.sub(r"\{[a-zA-Z_][a-zA-Z0-9_]*\}", "'2024-01-01'", out)
    return out


def _check_balanced_delimiters(sql: str) -> list[str]:
    """Return structural errors for unbalanced ``()`` / ``[]`` outside string literals."""
    stack: list[tuple[str, int]] = []
    i = 0
    length = len(sql)
    while i < length:
        ch = sql[i]
        if ch == "'":
            i += 1
            while i < length:
                if sql[i] == "'":
                    if i + 1 < length and sql[i + 1] == "'":
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
            continue
        if ch == '"':
            i += 1
            while i < length:
                if sql[i] == '"':
                    if i + 1 < length and sql[i + 1] == '"':
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
            continue
        if ch == "(":
            stack.append(("parenthesis", i))
        elif ch == ")":
            if not stack or stack[-1][0] != "parenthesis":
                return [f"unmatched ')' near column {i + 1}"]
            stack.pop()
        elif ch == "[":
            stack.append(("bracket", i))
        elif ch == "]":
            if not stack or stack[-1][0] != "bracket":
                return [f"unmatched ']' near column {i + 1}"]
            stack.pop()
        i += 1

    errors: list[str] = []
    for kind, pos in stack:
        label = "parenthesis" if kind == "parenthesis" else "bracket"
        errors.append(f"unclosed {label} opened near column {pos + 1}")
    return errors


def parse_trino_golden_query_sql(
    prepared_sql: str,
) -> tuple[Any | None, str | None]:
    """Parse placeholder-substituted SQL with the Trino dialect."""
    if sqlglot is None:
        return None, "sqlglot not installed"
    try:
        return sqlglot.parse_one(prepared_sql, dialect=_TRINO_DIALECT), None
    except Exception as exc:
        return None, str(exc)


def validate_trino_sql_syntax(
    sql: str,
    *,
    query_label: str,
) -> tuple[list[str], list[str]]:
    """Return blocking Trino syntax errors and non-blocking warnings for one query."""
    errors: list[str] = []
    warnings: list[str] = []
    if not (sql or "").strip():
        errors.append(f"{query_label}: empty SQL block")
        return errors, warnings

    prepared = substitute_sql_placeholders(sql)
    for message in _check_balanced_delimiters(prepared):
        errors.append(f"{query_label}: {message}")
    if errors:
        return errors, warnings

    if sqlglot is None:
        warnings.append(
            f"{query_label}: sqlglot not installed — Trino SQL syntax was not validated"
        )
        return errors, warnings

    _, parse_error = parse_trino_golden_query_sql(prepared)
    if parse_error:
        errors.append(f"{query_label}: invalid Trino SQL syntax ({parse_error})")
    return errors, warnings


def normalize_table_ref(
    catalog: str | None,
    schema: str | None,
    table: str | None,
) -> Optional[tuple[str, str]]:
    """Return ``(database_name, table_name)`` for metadata lookup.

    Trino references such as ``hive.datalake_langfuse_clean.scores`` map to
    ``datalake_langfuse_clean.scores`` — the ``hive`` catalog prefix is ignored.
    """
    catalog_name = (catalog or "").strip().lower()
    schema_name = (schema or "").strip()
    table_name = (table or "").strip()
    if not table_name:
        return None
    if catalog_name == _HIVE_CATALOG_PREFIX:
        if not schema_name:
            return None
        return schema_name.lower(), table_name.lower()
    if not schema_name:
        return None
    return schema_name.lower(), table_name.lower()


def table_refs_in_sql(sql: str) -> list[tuple[str, str]]:
    """Distinct ``(schema, table)`` pairs from FROM/JOIN, first-seen order."""
    seen: set[tuple[str, str]] = set()
    out: list[tuple[str, str]] = []
    for schema, table in _SQL_TABLE_REF_RE.findall(sql or ""):
        key = (schema.lower(), table.lower())
        if key not in seen:
            seen.add(key)
            out.append((schema, table))
    return out


class GoldenQuerySchemaClient(Protocol):
    """Lookup tables and columns for golden-query validation."""

    def table_exists(self, schema: str, table: str) -> bool: ...

    def column_names_for_table(self, schema: str, table: str) -> Optional[set[str]]: ...

    def table_source_hint(self, schema: str, table: str) -> str:
        """Human-readable hint for error messages (e.g. metadata file path)."""
        ...


def _cte_names(expression: Any) -> set[str]:
    names: set[str] = set()
    for cte in expression.find_all(exp.CTE):
        alias = cte.alias_or_name
        if alias:
            names.add(str(alias).lower())
    return names


def _tables_in_from_clause(select: Any) -> list[Any]:
    tables: list[Any] = []
    from_ = select.args.get("from")
    if from_ is not None:
        tables.extend(from_.find_all(exp.Table))
    for join in select.args.get("joins") or []:
        tables.extend(join.find_all(exp.Table))
    return tables


def _enclosing_select(node: Any) -> Any | None:
    current = node
    while current is not None:
        if isinstance(current, exp.Select):
            return current
        current = current.parent
    return None


def _select_output_aliases(select: Any) -> set[str]:
    aliases: set[str] = set()
    for projection in select.expressions or []:
        if isinstance(projection, exp.Alias):
            alias = projection.alias
            if alias:
                aliases.add(str(alias).lower())
            continue
        if getattr(projection, "alias", None):
            aliases.add(str(projection.alias).lower())
    return aliases


def _output_aliases_in_query(expression: Any) -> set[str]:
    aliases: set[str] = set()
    for select in expression.find_all(exp.Select):
        aliases.update(_select_output_aliases(select))
    return aliases


def _alias_maps_for_select(
    select: Any,
    cte_names: set[str],
) -> tuple[dict[str, tuple[str, str]], set[str]]:
    """Return physical-table aliases and derived (CTE/subquery) aliases in scope."""
    physical_aliases: dict[str, tuple[str, str]] = {}
    derived_aliases: set[str] = set()
    for table in _tables_in_from_clause(select):
        normalized = normalize_table_ref(table.catalog, table.db, table.name)
        alias = str(table.alias_or_name or table.name or "").lower()
        table_name = str(table.name or "").lower()
        if not alias:
            continue
        if normalized:
            physical_aliases[alias] = normalized
            if table_name and table_name not in physical_aliases:
                physical_aliases[table_name] = normalized
            continue
        if table_name in cte_names:
            derived_aliases.add(alias)
    return physical_aliases, derived_aliases


def _physical_tables_from_expression(expression: Any) -> list[tuple[str, str]]:
    seen: set[tuple[str, str]] = set()
    out: list[tuple[str, str]] = []
    for table in expression.find_all(exp.Table):
        normalized = normalize_table_ref(table.catalog, table.db, table.name)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        out.append(normalized)
    return out


def validate_golden_query_sql(
    sql: str,
    *,
    query_label: str,
    client: GoldenQuerySchemaClient,
    schema_source_label: str = "metadata",
) -> tuple[list[str], list[str]]:
    """Return ``(errors, warnings)`` for one golden-query SQL body."""
    errors: list[str] = []
    warnings: list[str] = []

    syntax_errors, syntax_warnings = validate_trino_sql_syntax(
        sql, query_label=query_label
    )
    errors.extend(syntax_errors)
    warnings.extend(syntax_warnings)
    if syntax_errors:
        return errors, warnings

    prepared = substitute_sql_placeholders(sql)
    expression = None
    if sqlglot is None:
        physical_tables = table_refs_in_sql(prepared)
    else:
        expression, parse_error = parse_trino_golden_query_sql(prepared)
        if parse_error:
            errors.append(f"{query_label}: invalid Trino SQL syntax ({parse_error})")
            return errors, warnings
        physical_tables = _physical_tables_from_expression(expression)

    if not physical_tables:
        warnings.append(
            f"{query_label}: no qualified schema.table references found — "
            f"skipping {schema_source_label} table/column checks"
        )
        return errors, warnings

    resolved_tables: list[tuple[str, str]] = []
    for schema, table in physical_tables:
        if not client.table_exists(schema, table):
            hint = client.table_source_hint(schema, table)
            errors.append(
                f"{query_label}: table `{schema}.{table}` not found in repo "
                f"{schema_source_label} ({hint})"
            )
        else:
            resolved_tables.append((schema.lower(), table.lower()))

    columns_by_table: dict[tuple[str, str], set[str]] = {}
    for schema, table in resolved_tables:
        cols = client.column_names_for_table(schema, table)
        if cols is None:
            hint = client.table_source_hint(schema, table)
            errors.append(
                f"{query_label}: could not load columns for `{schema}.{table}` "
                f"from repo {schema_source_label} ({hint})"
            )
        elif not cols:
            warnings.append(
                f"{query_label}: `{schema}.{table}` has no documented columns "
                f"in repo {schema_source_label}"
            )
        else:
            columns_by_table[(schema, table)] = cols

    if sqlglot is None:
        warnings.append(
            f"{query_label}: sqlglot not installed — column references not validated"
        )
        return errors, warnings

    if expression is None:
        expression, parse_error = parse_trino_golden_query_sql(prepared)
        if parse_error:
            errors.append(f"{query_label}: invalid Trino SQL syntax ({parse_error})")
            return errors, warnings

    cte_names = _cte_names(expression)
    output_aliases = _output_aliases_in_query(expression)
    physical_keys = set(columns_by_table.keys())

    for column in expression.find_all(exp.Column):
        col_name = (column.name or "").strip().lower()
        if not col_name or col_name == "*":
            continue
        table_ref = (column.table or "").strip().lower()
        if table_ref in cte_names or col_name in output_aliases:
            continue

        select = _enclosing_select(column)
        if select is None:
            continue
        physical_aliases, derived_aliases = _alias_maps_for_select(select, cte_names)

        if table_ref:
            if table_ref in derived_aliases:
                continue
            physical = physical_aliases.get(table_ref)
            if not physical:
                warnings.append(
                    f"{query_label}: column `{table_ref}.{col_name}` references an "
                    f"unresolved alias/CTE — not checked against {schema_source_label}"
                )
                continue
            known = columns_by_table.get(physical)
            if known is not None and col_name not in known:
                errors.append(
                    f"{query_label}: column `{col_name}` not found on "
                    f"`{physical[0]}.{physical[1]}` (repo {schema_source_label})"
                )
            continue

        matches = [
            pt for pt in physical_keys if col_name in columns_by_table.get(pt, set())
        ]
        if not matches:
            tables_human = ", ".join(f"`{s}.{t}`" for s, t in sorted(physical_keys))
            errors.append(
                f"{query_label}: unqualified column `{col_name}` not found on any "
                f"referenced table ({tables_human})"
            )

    return errors, warnings


def validate_golden_queries(
    golden_queries: list[Any],
    *,
    client: GoldenQuerySchemaClient,
    schema_source_label: str = "metadata",
) -> tuple[list[str], list[str]]:
    """Validate every parsed golden query; ``golden_queries`` items need ``.name`` and ``.sql``."""
    errors: list[str] = []
    warnings: list[str] = []
    if not golden_queries:
        return errors, warnings
    for idx, gq in enumerate(golden_queries, start=1):
        label = getattr(gq, "name", None) or f"Query {idx}"
        q_errors, q_warnings = validate_golden_query_sql(
            getattr(gq, "sql", "") or "",
            query_label=label,
            client=client,
            schema_source_label=schema_source_label,
        )
        errors.extend(q_errors)
        warnings.extend(q_warnings)
    return errors, warnings
