"""Tests for Databricks-to-Spark SQL transpiler."""

import pytest

from bietlejuice.transpiler.databricks_to_spark import (
    DatabricksToSparkTranspiler,
    needs_transpilation,
)


class TestNeedsTranspilation:
    def test_clean_sql_no_findings(self):
        sql = "SELECT id, name FROM schema.table WHERE dt >= '{load_start_date}'"
        assert needs_transpilation(sql) == []

    def test_qualify_detected(self):
        sql = (
            "SELECT id, name, ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts) AS rn\n"
            "FROM schema.table\n"
            "QUALIFY rn = 1"
        )
        findings = needs_transpilation(sql)
        assert len(findings) == 1
        assert "QUALIFY" in findings[0]

    def test_group_by_all_not_detected(self):
        sql = "SELECT category, COUNT(*) AS cnt\nFROM schema.table\nGROUP BY ALL"
        findings = needs_transpilation(sql)
        assert len(findings) == 0

    def test_iff_detected(self):
        sql = "SELECT IFF(status = 'active', 1, 0) AS is_active FROM schema.table"
        findings = needs_transpilation(sql)
        assert len(findings) == 1
        assert "IFF" in findings[0]

    def test_datediff_3arg_detected(self):
        sql = "SELECT DATEDIFF(DAY, start_date, end_date) AS days FROM schema.table"
        findings = needs_transpilation(sql)
        assert len(findings) == 1
        assert "DATEDIFF" in findings[0]

    def test_cast_shorthand_detected(self):
        sql = "SELECT col::STRING FROM schema.table"
        findings = needs_transpilation(sql)
        assert len(findings) == 1
        assert "::STRING" in findings[0]

    def test_select_except_detected(self):
        sql = "SELECT * EXCEPT(col1, col2) FROM schema.table"
        findings = needs_transpilation(sql)
        assert len(findings) == 1
        assert "EXCEPT" in findings[0]

    def test_variant_access_detected(self):
        sql = "SELECT payload:event_name FROM schema.table"
        findings = needs_transpilation(sql)
        assert len(findings) == 1

    def test_multiple_constructs(self):
        sql = (
            "SELECT IFF(a, 1, 0),\n"
            "  col::INT,\n"
            "  DATEDIFF(DAY, dt1, dt2)\n"
            "FROM schema.table"
        )
        findings = needs_transpilation(sql)
        assert len(findings) == 3


class TestTranspiler:
    @pytest.fixture
    def transpiler(self):
        return DatabricksToSparkTranspiler()

    def test_clean_sql_skipped(self, transpiler):
        sql = "SELECT id, name FROM schema.table WHERE id > 0"
        result = transpiler.transpile_sql(sql)
        assert result.skipped is True
        assert result.transpiled == sql
        assert result.error is None

    def test_empty_sql(self, transpiler):
        result = transpiler.transpile_sql("")
        assert result.transpiled == ""
        assert result.error is None

    def test_template_params_preserved(self, transpiler):
        sql = (
            "SELECT IFF(a > 0, 1, 0) AS flag\n"
            "FROM schema.table\n"
            "WHERE dt >= '{load_start_date}' AND dt < '{load_end_date}'"
        )
        result = transpiler.transpile_sql(sql)
        assert result.error is None
        assert result.transpiled is not None
        assert "{load_start_date}" in result.transpiled
        assert "{load_end_date}" in result.transpiled

    def test_double_braces_preserved(self, transpiler):
        sql = (
            "SELECT IFF(a > 0, 1, 0) AS flag\n"
            "FROM schema.table\n"
            "WHERE name = '{{literal_brace}}'"
        )
        result = transpiler.transpile_sql(sql)
        assert result.error is None
        assert result.transpiled is not None
        assert "{{" in result.transpiled
        assert "}}" in result.transpiled

    def test_iff_to_if(self, transpiler):
        sql = "SELECT IFF(status = 'active', 1, 0) AS is_active FROM schema.table"
        result = transpiler.transpile_sql(sql)
        assert result.error is None
        assert result.transpiled is not None
        assert result.changed is True
        upper = result.transpiled.upper()
        assert "IFF" not in upper or "IF(" in upper

    def test_cast_shorthand_to_cast(self, transpiler):
        sql = "SELECT col::STRING AS col_str FROM schema.table"
        result = transpiler.transpile_sql(sql)
        assert result.error is None
        assert result.transpiled is not None
        assert result.changed is True
        assert "CAST" in result.transpiled.upper()

    def test_trailing_newline_preserved(self, transpiler):
        sql = "SELECT IFF(a, 1, 0) FROM schema.table\n"
        result = transpiler.transpile_sql(sql)
        assert result.transpiled is not None
        assert result.transpiled.endswith("\n")

    def test_invalid_sql_returns_error(self, transpiler):
        sql = "SELECT IFF(a, 1, 0) FROM WHERE GROUP BY ALL HAVING"
        result = transpiler.transpile_sql(sql)
        assert result.error is not None or result.transpiled is not None

    def test_datediff_day_3arg_to_spark_2arg_preserves_sign(self, transpiler):
        sql = (
            "SELECT COALESCE(DATEDIFF(DAY, sia.ts_search, sia.ts_visit_booked) <= 14, FALSE) "
            "AS is_within_14_days FROM schema.table"
        )
        result = transpiler.transpile_sql(sql)
        assert result.error is None
        assert result.transpiled is not None
        assert "DATEDIFF(DAY," not in result.transpiled.upper()
        assert "sia.ts_visit_booked" in result.transpiled
        assert "sia.ts_search" in result.transpiled
        visit_pos = result.transpiled.index("sia.ts_visit_booked")
        search_pos = result.transpiled.index("sia.ts_search")
        assert visit_pos < search_pos

    def test_datediff_month_3arg_to_timestampdiff(self, transpiler):
        sql = "SELECT DATEDIFF(MONTH, dt_signed, CURRENT_TIMESTAMP()) AS months FROM schema.table"
        result = transpiler.transpile_sql(sql)
        assert result.error is None
        assert result.transpiled is not None
        upper = result.transpiled.upper()
        assert "TIMESTAMPDIFF(MONTH" in upper
        signed_pos = result.transpiled.index("dt_signed")
        current_pos = upper.index("CURRENT_TIMESTAMP")
        assert signed_pos < current_pos

    def test_datediff_2arg_grace_period_preserved_when_transpiling(self, transpiler):
        sql = (
            "SELECT IFF(a > 0, 1, 0) AS flag,\n"
            "  IFNULL(DATEDIFF(pcd.dt_ended_propose, DATE(c.ts_began)) <= 10, FALSE) "
            "AS is_grace_period_cancelled\n"
            "FROM schema.table"
        )
        result = transpiler.transpile_sql(sql)
        assert result.error is None
        assert result.transpiled is not None
        assert "DATEDIFF(DAY," not in result.transpiled.upper()
        ended_pos = result.transpiled.index("pcd.dt_ended_propose")
        began_pos = result.transpiled.index("c.ts_began")
        assert ended_pos < began_pos
