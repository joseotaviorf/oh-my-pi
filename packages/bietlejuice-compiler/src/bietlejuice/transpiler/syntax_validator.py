"""Validate transpiled SQL syntax by parsing with SQLGlot in Spark dialect."""

from __future__ import annotations

import re
from typing import List, Optional, Tuple

from sqlglot import parse
from sqlglot.errors import ParseError

_QUOTED_TEMPLATE_RE = re.compile(r"'\{[a-z_][a-z0-9_]*\}'")
_BARE_TEMPLATE_RE = re.compile(r"\{([a-z_][a-z0-9_]*)\}")


def _replace_params_with_literals(sql: str) -> str:
    sql = sql.replace("{{", "").replace("}}", "")
    sql = _QUOTED_TEMPLATE_RE.sub("'__placeholder__'", sql)
    return _BARE_TEMPLATE_RE.sub("'__placeholder__'", sql)


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
