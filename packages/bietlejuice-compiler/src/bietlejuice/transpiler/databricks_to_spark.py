"""Transpile SQL from Databricks dialect to Spark 3.5 (EMR) using SQLGlot.

Only queries containing Databricks-only constructs are transpiled.
Queries that are already dual-runtime compatible are returned unchanged.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import List, Optional

import sqlglot
from sqlglot import exp, transpile
from sqlglot.errors import ParseError

TEMPLATE_PARAMS = [
    "load_start_date",
    "load_end_date",
    "environment",
    "bucket",
    "dag_name",
    "schema",
    "table_name",
    "partitions",
]

_TEMPLATE_PARAM_RE = re.compile(
    r"\{(" + "|".join(re.escape(p) for p in TEMPLATE_PARAMS) + r")\}"
)

CRITICAL_PATTERN = re.compile(
    r"\bQUALIFY\b"
    r"|\bIFF\s*\("
    r"|\bDECODE\s*\("
    r"|\bDATEDIFF\s*\(\s*['\"]?(YEAR|QUARTER|MONTH|WEEK|DAY|HOUR|MINUTE|SECOND|MILLISECOND|MICROSECOND)\b"
    r"|[a-zA-Z_][a-zA-Z0-9_]*:\[?[\"']?[a-zA-Z_]"
    r"|::(ARRAY|BIGINT|BOOLEAN|DATE|DOUBLE|FLOAT|INT|INTEGER|LONG|MAP|SHORT|STRING|STRUCT|TIMESTAMP|TINYINT|VARIANT|DECIMAL)"
    r"|\*\s+EXCEPT\s*\("
    r"|\bWITH\s+RECURSIVE\b",
    re.IGNORECASE,
)


def needs_transpilation(sql: str) -> List[str]:
    """Return line snippets for each Databricks-only construct found.

    Empty list means the SQL is already dual-runtime compatible.
    """
    findings = []
    for line_no, line in enumerate(sql.splitlines(), start=1):
        if CRITICAL_PATTERN.search(line):
            findings.append(f"L{line_no}: {line.strip()[:120]}")
    return findings


@dataclass
class TranspileResult:
    original: str
    transpiled: Optional[str] = None
    error: Optional[str] = None
    changed: bool = False
    skipped: bool = False
    construct_warnings: List[str] = field(default_factory=list)


_POST_PROCESS_PATTERNS = [
    (re.compile(r"\bIFF\s*\(", re.IGNORECASE), "IF("),
    (re.compile(r"\bDECODE\s*\(", re.IGNORECASE), None),
]


class DatabricksToSparkTranspiler:
    SOURCE_DIALECT = "databricks"
    TARGET_DIALECT = "spark"

    def _fix_datediff(self, tree: sqlglot.Expression) -> sqlglot.Expression:
        """Convert 3-arg DATEDIFF to Spark-compatible form.

        Databricks ``DATEDIFF(unit, start, end)`` is parsed by SQLGlot with
        ``expression=start`` and ``this=end``. Spark 2-arg ``DATEDIFF(end, start)``
        uses the same slot assignment, so DAY only drops the unit. Other units
        become ``TIMESTAMPDIFF(unit, start, end)``.
        """
        for dd in list(tree.find_all(exp.DateDiff)):
            unit = dd.args.get("unit")
            if unit is None:
                continue
            unit_str = unit.name.upper()
            start = dd.args["expression"]
            end = dd.args["this"]
            if unit_str == "DAY":
                new_node = exp.DateDiff(this=end.copy(), expression=start.copy())
            else:
                new_node = exp.TimestampDiff(
                    this=end.copy(),
                    expression=start.copy(),
                    unit=unit.copy(),
                )
            dd.replace(new_node)
        return tree

    def _apply_post_processing(self, sql: str) -> str:
        """Apply simple mechanical substitutions that SQLGlot doesn't handle."""
        result = re.sub(r"\bIFF\s*\(", "IF(", sql, flags=re.IGNORECASE)
        return result

    def _protect_template_params(self, sql: str) -> str:
        sql = sql.replace("{{", "__DBLBRACE__").replace("}}", "__DBLRBRACE__")
        sql = _TEMPLATE_PARAM_RE.sub(r"__TMPL_\1__", sql)
        return sql

    def _restore_template_params(self, sql: str) -> str:
        sql = re.sub(r"__TMPL_(\w+)__", r"{\1}", sql)
        sql = sql.replace("__DBLBRACE__", "{{").replace("__DBLRBRACE__", "}}")
        return sql

    def transpile_sql(self, sql: str) -> TranspileResult:
        result = TranspileResult(original=sql)

        if not sql.strip():
            result.transpiled = sql
            return result

        findings = needs_transpilation(sql)
        if not findings:
            result.transpiled = sql
            result.skipped = True
            return result

        result.construct_warnings = findings
        protected = self._protect_template_params(sql)

        try:
            transpiled_parts = transpile(
                protected,
                read=self.SOURCE_DIALECT,
                write=self.TARGET_DIALECT,
                pretty=True,
            )
        except ParseError as e:
            result.error = f"SQLGlot parse error: {e}"
            return result
        except Exception as e:
            result.error = f"Transpilation error: {e}"
            return result

        if not transpiled_parts:
            result.error = "Transpilation returned empty result"
            return result

        try:
            fixed_parts = []
            for part in transpiled_parts:
                tree = sqlglot.parse_one(part, dialect=self.TARGET_DIALECT)
                tree = self._fix_datediff(tree)
                fixed_parts.append(tree.sql(dialect=self.TARGET_DIALECT, pretty=True))
        except ParseError as e:
            result.error = f"Post-transpile parse error: {e}"
            return result
        except Exception as e:
            result.error = f"Post-transpile fix error: {e}"
            return result

        joined = ";\n".join(fixed_parts)
        joined = self._apply_post_processing(joined)
        restored = self._restore_template_params(joined)

        if sql.endswith("\n") and not restored.endswith("\n"):
            restored += "\n"

        result.transpiled = restored
        result.changed = restored != sql
        return result

    def transpile_file(self, file_path: str, dry_run: bool = False) -> TranspileResult:
        try:
            with open(file_path, encoding="utf-8") as f:
                original = f.read()
        except FileNotFoundError:
            return TranspileResult(original="", error=f"File not found: {file_path}")

        result = self.transpile_sql(original)

        if not dry_run and result.transpiled is not None and result.changed:
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(result.transpiled)

        return result
