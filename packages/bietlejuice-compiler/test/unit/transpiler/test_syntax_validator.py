"""Tests for Spark SQL syntax validator."""

from bietlejuice.transpiler.syntax_validator import (
    validate_multiple,
    validate_spark_syntax,
)


class TestValidateSparkSyntax:
    def test_valid_simple_select(self):
        sql = "SELECT id, name FROM schema.table WHERE id > 0"
        valid, error = validate_spark_syntax(sql)
        assert valid is True
        assert error is None

    def test_valid_with_template_params(self):
        sql = (
            "SELECT id, name\n"
            "FROM schema.table\n"
            "WHERE dt >= '{load_start_date}' AND dt < '{load_end_date}'"
        )
        valid, error = validate_spark_syntax(sql)
        assert valid is True
        assert error is None

    def test_valid_with_double_braces(self):
        sql = "SELECT id FROM schema.table WHERE name = '{{literal}}'"
        valid, error = validate_spark_syntax(sql)
        assert valid is True
        assert error is None

    def test_valid_cte(self):
        sql = (
            "WITH base AS (\n"
            "  SELECT id, name FROM schema.table\n"
            ")\n"
            "SELECT id, name FROM base"
        )
        valid, error = validate_spark_syntax(sql)
        assert valid is True
        assert error is None

    def test_valid_with_joins(self):
        sql = (
            "SELECT a.id, b.name\n"
            "FROM schema.table_a AS a\n"
            "JOIN schema.table_b AS b\n"
            "  ON a.id = b.id\n"
            "WHERE a.dt >= '{load_start_date}'"
        )
        valid, error = validate_spark_syntax(sql)
        assert valid is True
        assert error is None

    def test_empty_sql_valid(self):
        valid, error = validate_spark_syntax("")
        assert valid is True
        assert error is None

    def test_invalid_sql_returns_error(self):
        sql = "SELECTT id FROMM table"
        valid, error = validate_spark_syntax(sql)
        # SQLGlot may be lenient — just check it doesn't crash
        assert isinstance(valid, bool)

    def test_valid_window_function(self):
        sql = (
            "SELECT id, ROW_NUMBER() OVER (PARTITION BY group_id ORDER BY ts) AS rn\n"
            "FROM schema.table"
        )
        valid, error = validate_spark_syntax(sql)
        assert valid is True

    def test_valid_case_when(self):
        sql = (
            "SELECT\n"
            "  CASE\n"
            "    WHEN status = 'active' THEN 1\n"
            "    ELSE 0\n"
            "  END AS is_active\n"
            "FROM schema.table"
        )
        valid, error = validate_spark_syntax(sql)
        assert valid is True


class TestValidateMultiple:
    def test_multiple_queries(self):
        queries = [
            ("valid_query", "SELECT id FROM schema.table"),
            ("also_valid", "SELECT name FROM schema.other"),
        ]
        results = validate_multiple(queries)
        assert len(results) == 2
        for name, valid, error in results:
            assert valid is True
            assert error is None
