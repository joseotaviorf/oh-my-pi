from tars_evals.dataset_quality import (
    exclusion_reason,
    is_sql_fragment,
    is_with_only_sql,
)


def test_exclusion_scaffolding_title():
    assert (
        exclusion_reason(
            question="Base CTE (reused by all golden queries)",
            expected_query="WITH foo AS (SELECT 1) SELECT * FROM foo",
        )
        == "scaffolding_title"
    )


def test_exclusion_full_reference_query_with_only():
    sql = "WITH date_dim AS (SELECT 1 AS x) SELECT * FROM date_dim"
    # strip final SELECT for with-only case
    with_only = "WITH date_dim AS (SELECT 1 AS x), final AS (SELECT 2)"
    assert (
        exclusion_reason(question="Full reference query", expected_query=with_only)
        == "scaffolding_title"
    )
    assert exclusion_reason(question="Monthly turnover", expected_query=sql) is None


def test_exclusion_uses_base_cte_comment():
    sql = "-- Uses base CTE above (tb_fl)\nSELECT week_start FROM tb_fl"
    assert (
        exclusion_reason(question="First listings by week", expected_query=sql)
        == "uses_base_cte"
    )


def test_exclusion_see_query_ref():
    sql = "WITH condo AS (\n    -- ... see Query 1 ...\n    SELECT 1\n)\nSELECT * FROM condo"
    assert (
        exclusion_reason(question="Adoption by month", expected_query=sql)
        == "see_query_ref"
    )


def test_exclusion_prepend_from_query():
    sql = "-- Prepend params from Query 1.\nWITH nps AS (SELECT 1) SELECT * FROM nps"
    assert (
        exclusion_reason(question="NPS volumes", expected_query=sql)
        == "prepend_from_query"
    )


def test_exclusion_external_cte_ref():
    sql = "SELECT month_start FROM unified_backlog_base GROUP BY 1"
    assert (
        exclusion_reason(question="Out of SLA Rate", expected_query=sql)
        == "external_cte_ref"
    )


def test_exclusion_canonical_base_title():
    sql = "SELECT 1 AS x"
    assert (
        exclusion_reason(question="Zendesk Canonical Base", expected_query=sql)
        == "scaffolding_title"
    )


def test_exclusion_chargehub_partial_title():
    sql = "WITH segment_allocation AS (SELECT 1) -- Then use Query 2"
    assert (
        exclusion_reason(
            question="Same query, but using Chargehub audiences",
            expected_query=sql,
        )
        == "chargehub_partial_title"
    )


def test_exclusion_unreplaced_curly_placeholder():
    sql = "SELECT 1 WHERE ts_created >= TIMESTAMP '{start_date}'"
    assert (
        exclusion_reason(question="Escalation rate", expected_query=sql)
        == "unreplaced_placeholder"
    )


def test_exclusion_unreplaced_angle_placeholder():
    sql = "SELECT 1 WHERE dt BETWEEN DATE('<start_date>') AND DATE('<end_date>')"
    assert (
        exclusion_reason(question="CSAT by month", expected_query=sql)
        == "unreplaced_placeholder"
    )


def test_exclusion_unreplaced_uppercase_placeholder():
    sql = 'SELECT SUM(TRY_CAST(REPLACE(f."<YYYYMM>", \',\', \'\') AS DOUBLE)) AS x FROM t'
    assert (
        exclusion_reason(question="Denominator", expected_query=sql)
        == "unreplaced_placeholder"
    )


def test_exclusion_bare_expression_stub_no_select():
    sql = (
        "-- Weekly cohort\n\n"
        "DATE_TRUNC('week', dhl.ts_publication) AS cohort_period\n\n"
        "-- Daily cohort\n\n"
        "CAST(dhl.ts_publication AS DATE) AS cohort_period"
    )
    assert is_sql_fragment(sql) is True
    assert (
        exclusion_reason(question="L2R weekly or daily", expected_query=sql)
        == "sql_fragment"
    )


def test_exclusion_with_only_sql():
    sql = "WITH chargehub_allocation AS (SELECT 1)"
    assert is_with_only_sql(sql) is True
    assert exclusion_reason(question="Recovery slice", expected_query=sql) == "with_only_sql"


def test_exclusion_sql_fragment():
    sql = "SELECT COUNT(*) AS total"
    assert is_sql_fragment(sql) is True
    assert exclusion_reason(question="Count total", expected_query=sql) == "sql_fragment"


def test_keeps_complete_metric_query():
    sql = (
        "SELECT DATE_TRUNC('month', dt) AS month_start, COUNT(*) AS n\n"
        "FROM dw.fact_events\n"
        "GROUP BY 1"
    )
    assert exclusion_reason(question="Monthly event volume", expected_query=sql) is None
