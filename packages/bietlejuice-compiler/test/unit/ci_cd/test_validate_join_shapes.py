"""Unit tests for validate_join_shapes.

Covers the two production incidents this validator exists to catch (the entities.sql
OR-join and the metric_events.sql range joins — see module docstring in
validate_join_shapes.py), the negative case that a naive line-based regex gets wrong (an
OR nested under AND beside a real equi-key must NOT be flagged), and the CLI's path/domain
expansion.
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from scripts.ci_cd.validate_join_shapes import (  # noqa: E402
    expand_paths,
    normalize_sql_for_join_lint,
    scan_sql_text,
)

# --- known-case regression: the actual incident, encoded as a test ---------------------

ENTITIES_SQL_BEFORE_FIX = """
WITH reservation AS (
    WITH reservation_base AS (
        SELECT
            rv.id AS id_entity,
            COALESCE(u.id, h.id_user) AS id_owner
        FROM
            datalake_kill_queue_clean.reservation AS rv
        LEFT JOIN
            datalake_ebdb_clean.house AS h
                ON h.id = rv.id_house
        LEFT JOIN
            datalake_ebdb_clean.house_listing_relation AS hl
                ON hl.id = rv.id_house
                AND hl.related_as = 'PROPERTY_OWNER'
        LEFT JOIN
            datalake_ebdb_clean.user AS u
                ON (u.id = hl.id_related
                OR u.uuid_person = hl.id_related)
    )
    SELECT * FROM reservation_base
)
SELECT * FROM reservation
"""


def test_entities_sql_before_fix_flags_the_or_join():
    violations = scan_sql_text(ENTITIES_SQL_BEFORE_FIX, "entities.sql")
    assert len(violations) == 1
    assert violations[0].kind == "OR_JOIN"
    assert "id_related" in violations[0].text
    # the flagged line must be the actual ON clause, not some other join in the file
    flagged_line = ENTITIES_SQL_BEFORE_FIX.splitlines()[violations[0].line_no - 1]
    assert "ON (u.id = hl.id_related" in flagged_line


def test_entities_sql_after_fix_is_clean():
    fixed = ENTITIES_SQL_BEFORE_FIX.replace(
        """LEFT JOIN
            datalake_ebdb_clean.user AS u
                ON (u.id = hl.id_related
                OR u.uuid_person = hl.id_related)""",
        """LEFT JOIN
            owner_resolved AS u
                ON u.id_relation = hl.id""",
    )
    assert scan_sql_text(fixed, "entities.sql") == []


def test_range_join_with_no_equi_key_is_flagged():
    sql = """
    SELECT ad.date, mp.metric
    FROM datalake_tiers.metric_period AS mp
    JOIN datalake_quintoandar.aux_date AS ad
        ON ad.date BETWEEN mp.dt_init AND mp.dt_end
    """
    violations = scan_sql_text(sql, "metric_events.sql")
    assert len(violations) == 1
    assert violations[0].kind == "NO_EQUI_KEY"


# --- the case naive regex gets wrong -----------------------------------------------------


def test_or_nested_under_and_beside_real_equi_key_is_not_flagged():
    """An OR that sits inside an AND alongside a genuine equi-predicate is still
    hash-joinable — Spark extracts the AND'd equi-key and applies the rest as a residual
    filter. A line-based `OR` grep flags this; the AST-based check must not."""
    sql = """
    SELECT cv.id_person
    FROM core_visit.visit AS cv
    INNER JOIN datalake_ebdb_clean.email_address AS ea
        ON cv.id_person = ea.id_person
        AND ea.email_type = 'H1'
        AND ea.dt_started <= cv.dt_address_referenced
        AND (ea.dt_ended IS NULL OR ea.dt_ended > cv.dt_address_referenced)
    """
    assert scan_sql_text(sql, "dim_contact.sql") == []


def test_plain_equi_join_is_not_flagged():
    sql = "SELECT a.x FROM t1 AS a JOIN t2 AS b ON a.id = b.id"
    assert scan_sql_text(sql, "clean.sql") == []


def test_one_side_unqualified_equi_key_is_not_flagged():
    """ON id_user_contract_final = u.id -- real equi-join, one side has no table alias."""
    sql = "SELECT u.x FROM t1 AS u JOIN t2 AS c ON c.id_user_contract_final = u.id"
    assert scan_sql_text(sql, "clean.sql") == []


def test_both_sides_unqualified_equi_key_is_not_flagged():
    """ON offer_id = sk_offer -- real equi-join, neither side has a table alias."""
    sql = "SELECT 1 FROM t1 AS a JOIN t2 AS b ON offer_id = sk_offer"
    assert scan_sql_text(sql, "clean.sql") == []


def test_same_alias_both_sides_is_still_flagged():
    """a.status = a.status_backup links no second relation -- not a cross-relation key."""
    sql = "SELECT 1 FROM t1 AS a JOIN t2 AS b ON a.status = a.status_backup"
    violations = scan_sql_text(sql, "clean.sql")
    assert len(violations) == 1
    assert violations[0].kind == "NO_EQUI_KEY"


def test_top_level_or_with_no_and_wrapper_is_flagged():
    sql = "SELECT a.x FROM t1 AS a JOIN t2 AS b ON a.id = b.id OR a.alt = b.alt"
    violations = scan_sql_text(sql, "clean.sql")
    assert len(violations) == 1
    assert violations[0].kind == "OR_JOIN"


def test_cross_join_and_using_are_not_flagged():
    sql = """
    SELECT a.x FROM t1 AS a
    CROSS JOIN t2 AS b
    JOIN t3 AS c USING (id)
    """
    assert scan_sql_text(sql, "clean.sql") == []


def test_two_identical_or_joins_each_get_their_own_line():
    """Content-based line lookup must not collapse two occurrences of the same pattern
    onto one line — each violation should point at its own ON clause."""
    sql = """
    SELECT 1
    FROM t1 AS a
    LEFT JOIN t2 AS b
        ON a.id = b.id
        OR a.alt = b.alt
    LEFT JOIN t3 AS c
        ON a.id = c.id
        OR a.alt = c.alt
    """
    violations = scan_sql_text(sql, "clean.sql")
    assert len(violations) == 2
    assert violations[0].line_no != violations[1].line_no


def test_unparseable_sql_is_reported_not_raised():
    violations = scan_sql_text("SELECT FROM WHERE (((", "broken.sql")
    assert len(violations) == 1
    assert violations[0].kind == "UNPARSEABLE"


# --- normalization -----------------------------------------------------------------------


def test_normalize_handles_quoted_bracket_params():
    """DATE('{load_start_date}') must become a valid string literal, not DATE(''DUMMY'')."""
    sql = "SELECT * FROM t WHERE d = DATE('{load_start_date}')"
    normalized = normalize_sql_for_join_lint(sql)
    assert normalized.count("''") == 0
    assert "'DUMMY'" in normalized


def test_normalize_preserves_line_count_across_multiline_block_comment():
    sql = "SELECT 1\n/* a\nmulti\nline\ncomment */\nFROM t\nJOIN u ON t.id = u.id"
    normalized = normalize_sql_for_join_lint(sql)
    assert normalized.count("\n") == sql.count("\n")


def test_normalize_unescapes_literal_brace_regex_quantifier():
    """Per databricks_conventions.mdc "Literal Braces": {{6}} is a literal-brace escape
    for a regex quantifier, not a Jinja-style block to replace wholesale. It must unescape
    to {6}, not become 'DUMMY' — that would split the string literal and make otherwise
    valid SQL UNPARSEABLE, an actual repo file this exact shape came from
    (people/enrich_learning/queries/enrich/content_completions.sql)."""
    sql = "SELECT CASE WHEN REGEXP_LIKE(x, '^[0-9]{{6}}$') THEN x END FROM t"
    normalized = normalize_sql_for_join_lint(sql)
    assert "{6}" in normalized
    assert "'DUMMY'" not in normalized


def test_normalize_unescapes_literal_brace_json_content():
    """{{"), "\\}} unescapes brace-by-brace, not as a matched {{...}} pair — a real shape
    from this repo's SQL (JSON-ish literal text with escaped braces)."""
    sql = r"""SELECT CONCAT('{{"a": "', x, '"\}}') FROM t"""
    normalized = normalize_sql_for_join_lint(sql)
    assert "'DUMMY'" not in normalized


def test_file_using_literal_brace_escape_stays_parseable_end_to_end():
    sql = """
    SELECT
        CASE WHEN REGEXP_LIKE(id_employee_internal, '^[0-9]{{6}}$') THEN id_employee_internal END AS id
    FROM t1 AS a
    JOIN t2 AS b ON a.id = b.id
    """
    violations = scan_sql_text(sql, "content_completions.sql")
    assert all(v.kind != "UNPARSEABLE" for v in violations)
    assert violations == []


# --- CLI path/domain expansion -------------------------------------------------------------


def test_expand_paths_file_is_returned_as_is(tmp_path):
    f = tmp_path / "one.sql"
    f.write_text("SELECT 1")
    assert expand_paths([str(f)]) == [f]


def test_expand_paths_directory_recurses(tmp_path):
    (tmp_path / "sub").mkdir()
    a = tmp_path / "a.sql"
    b = tmp_path / "sub" / "b.sql"
    a.write_text("SELECT 1")
    b.write_text("SELECT 1")
    (tmp_path / "not_sql.txt").write_text("ignore me")
    result = expand_paths([str(tmp_path)])
    assert set(result) == {a, b}


def test_expand_paths_nonexistent_path_errors():
    with pytest.raises(SystemExit):
        expand_paths(["/no/such/path/at/all.sql"])
