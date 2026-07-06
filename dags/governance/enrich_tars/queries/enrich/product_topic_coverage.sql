-- Daily snapshot of product x topic coverage.
-- Joins DataHub product catalog against actual Tars usage to surface gaps.
WITH products AS (
    SELECT
        product_slug,
        product_name,
        datahub_domain,
        is_test
    FROM
        datalake_tars.datahub_product_glossary
    WHERE
        is_test = FALSE
),
topics AS (
    SELECT DISTINCT
        business_domain
    FROM
        datalake_tars.query_annotations
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
        AND business_domain IS NOT NULL
        AND business_domain != 'unknown'
),
usage AS (
    SELECT
        asset_slug AS product_slug,
        business_domain,
        COUNT(DISTINCT id_session) AS sessions,
        COUNT(DISTINCT id_query) AS queries,
        SUM(urn_hit_count) AS urn_hits
    FROM
        datalake_tars.datahub_asset_usage
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
        AND asset_type = 'dataProduct'
    GROUP BY
        asset_slug,
        business_domain
),
-- Heuristic: which Tars topics are expected to use which DataHub domains
domain_topic_map AS (
    SELECT 'For Rent' AS business_domain, 'for_rent' AS expected_datahub_domain
    UNION ALL SELECT 'For Rent', 'growth'
    UNION ALL SELECT 'For Rent', 'support_and_services'
    UNION ALL SELECT 'For Sale', 'growth'
    UNION ALL SELECT 'Fintech', 'fintech'
    UNION ALL SELECT 'Conversational', 'support_and_services'
    UNION ALL SELECT 'Conversational', 'fintech'
    UNION ALL SELECT 'Growth', 'growth'
    UNION ALL SELECT 'Agents', 'growth'
    UNION ALL SELECT 'Supply', 'growth'
    UNION ALL SELECT 'Other', 'for_rent'
    UNION ALL SELECT 'Other', 'growth'
    UNION ALL SELECT 'Other', 'fintech'
    UNION ALL SELECT 'Other', 'support_and_services'
    UNION ALL SELECT 'Other', 'untagged'
),
cross_joined AS (
    SELECT
        p.product_slug,
        p.product_name,
        p.datahub_domain,
        t.business_domain
    FROM
        products AS p
    CROSS JOIN
        topics AS t
)
SELECT
    cj.product_slug,
    cj.product_name,
    cj.datahub_domain,
    cj.business_domain,
    COALESCE(u.urn_hits, 0) AS urn_hits,
    COALESCE(u.sessions, 0) AS sessions,
    COALESCE(u.queries, 0) AS queries,
    u.product_slug IS NOT NULL AS is_used,
    dtm.expected_datahub_domain IS NOT NULL AS expected_domain_match,
    DATE("{load_start_date}") AS dt_reference,
    YEAR(DATE("{load_start_date}")) AS year,
    MONTH(DATE("{load_start_date}")) AS month,
    DAY(DATE("{load_start_date}")) AS day
FROM
    cross_joined AS cj
LEFT JOIN
    usage AS u
        ON cj.product_slug = u.product_slug
        AND cj.business_domain = u.business_domain
LEFT JOIN
    domain_topic_map AS dtm
        ON cj.business_domain = dtm.business_domain
        AND cj.datahub_domain = dtm.expected_datahub_domain
