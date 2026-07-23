"""Validate transpiled SQL syntax by parsing with SQLGlot in Spark dialect."""

from __future__ import annotations

import re
from typing import List, Optional, Tuple

from sqlglot import parse
from sqlglot.errors import ParseError

from bietlejuice.transpiler.databricks_to_spark import TEMPLATE_PARAMS

_TEMPLATE_PARAM_RE = re.compile(
    r"\{(" + "|".join(re.escape(p) for p in TEMPLATE_PARAMS) + r")\}"
)

_LITERAL_DEFAULTS = {
    "load_start_date": "2026-01-01",
    "load_end_date": "2026-01-02",
    "environment": "prod",
    "bucket": "s3://test-bucket",
    "dag_name": "test_dag",
    "schema": "test_schema",
    "table_name": "test_table",
    "partitions": "year=2026/month=01/day=01",
}


def _replace_params_with_literals(sql: str) -> str:
    sql = sql.replace("{{", "").replace("}}", "")

    def _replacer(match: re.Match) -> str:
        param = match.group(1)
        return _LITERAL_DEFAULTS.get(param, "'placeholder'")

    return _TEMPLATE_PARAM_RE.sub(_replacer, sql)


def validate_spark_syntax(sql: str) -> Tuple[bool, Optional[str]]:
    if not sql.strip():
        return True, None

    test_sql = _replace_params_with_literals(sql)

    try:
        parse(test_sql, dialect="spark")
        return True, None
    except ParseError as e:
        return False, str(e)


def validate_multiple(
    queries: List[Tuple[str, str]],
) -> List[Tuple[str, bool, Optional[str]]]:
    results = []
    for name, sql in queries:
        valid, error = validate_spark_syntax(sql)
        results.append((name, valid, error))
    return results
