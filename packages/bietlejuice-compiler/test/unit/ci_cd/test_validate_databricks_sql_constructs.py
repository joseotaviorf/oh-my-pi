"""Unit tests for validate_databricks_sql_constructs.

Pins the PR #27712 trailing-comma ParseException (sqlglot accepts it; Spark does not)
and keeps a smoke check that Databricks-only constructs are still flagged.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from scripts.ci_cd.validate_databricks_sql_constructs import (  # noqa: E402
    _TRAILING_COMMA_CONSTRUCT,
    scan_sql_text,
)

# --- PR #27712 regression --------------------------------------------------------------

DEAL_SIMULATION_AGG_BEFORE_FIX = """
WITH simulation_agg AS (
  SELECT
    consorcio_simulation.id_lead,
    COUNT(*) AS total_simulations,
   ROUND(
      AVG(
        consorcio_simulation.credit_value
      ),
     2
   ) AS avg_simulation_credit_value,
  FROM
    datalake_consorcio_clean.simulation AS consorcio_simulation
  GROUP BY
    consorcio_simulation.id_lead
)
SELECT id_lead FROM simulation_agg
"""


def test_pr_27712_trailing_comma_before_from_is_flagged():
    violations = scan_sql_text(DEAL_SIMULATION_AGG_BEFORE_FIX, "deal.sql")
    trailing = [v for v in violations if v.construct == _TRAILING_COMMA_CONSTRUCT]
    assert len(trailing) == 1
    assert (
        trailing[0].line_no
        == DEAL_SIMULATION_AGG_BEFORE_FIX.splitlines().index(
            "   ) AS avg_simulation_credit_value,"
        )
        + 1
    )
    assert "avg_simulation_credit_value," in trailing[0].text


def test_simulation_agg_without_trailing_comma_is_clean():
    fixed = DEAL_SIMULATION_AGG_BEFORE_FIX.replace(
        "   ) AS avg_simulation_credit_value,",
        "   ) AS avg_simulation_credit_value",
    )
    assert scan_sql_text(fixed, "deal.sql") == []


def test_trailing_comma_inside_line_comment_is_ignored():
    sql = """
    SELECT
      id
    -- trailing,
    FROM t
    """
    assert scan_sql_text(sql, "comment.sql") == []


def test_trailing_comma_inside_block_comment_is_ignored():
    sql = """
    SELECT
      id
      /* extra_col,
      FROM nowhere */
    FROM t
    """
    assert scan_sql_text(sql, "block_comment.sql") == []


def test_trailing_comma_inside_string_is_ignored():
    sql = """
    SELECT
      'value,
FROM nowhere' AS x
    FROM t
    """
    assert scan_sql_text(sql, "string.sql") == []


def test_trailing_comma_before_where_is_flagged():
    sql = """
    SELECT
      id,
    WHERE id > 0
    """
    violations = scan_sql_text(sql, "where.sql")
    assert len(violations) == 1
    assert violations[0].construct == _TRAILING_COMMA_CONSTRUCT
    assert violations[0].text.endswith(",")


def test_trailing_comma_before_group_by_is_flagged():
    sql = """
    SELECT
      id,
      COUNT(*) AS n,
    GROUP BY
      id
    """
    violations = scan_sql_text(sql, "group.sql")
    assert len(violations) == 1
    assert violations[0].construct == _TRAILING_COMMA_CONSTRUCT


def test_keyword_named_column_is_not_flagged():
    """superset query.sql: executed_sql, then a column named limit — not LIMIT 10."""
    sql = """
    SELECT
      executed_sql,
      limit,
      select_as_cta
    FROM t
    """
    trailing = [
        v
        for v in scan_sql_text(sql, "query.sql")
        if v.construct == _TRAILING_COMMA_CONSTRUCT
    ]
    assert trailing == []


def test_trailing_comma_before_limit_clause_is_flagged():
    sql = """
    SELECT
      id,
    LIMIT 10
    """
    violations = scan_sql_text(sql, "limit.sql")
    assert len(violations) == 1
    assert violations[0].construct == _TRAILING_COMMA_CONSTRUCT


def test_qualify_is_still_flagged():
    sql = """
    SELECT id
    FROM t
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts) = 1
    """
    violations = scan_sql_text(sql, "qualify.sql")
    assert any(v.construct == "QUALIFY" for v in violations)
