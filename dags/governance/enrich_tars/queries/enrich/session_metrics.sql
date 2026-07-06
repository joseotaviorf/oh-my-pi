WITH session_base AS (
    SELECT
        id_session,
        user,
        session_source,
        business_domain,
        is_success,
        response_category,
        ts_started,
        ts_ended,
        urn_count,
        data_product_count,
        dataset_count,
        depth_tier,
        year,
        month,
        day
    FROM
        datalake_tars.query_annotations
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
),
-- Derive first user / source per session (all queries in a session share these)
session_identity AS (
    SELECT
        id_session,
        MIN(user) AS user,
        MIN(session_source) AS session_source,
        MIN(business_domain) AS dominant_business_domain,
        MIN(ts_started) AS ts_session_start,
        MAX(ts_ended) AS ts_session_end,
        MIN(year) AS year,
        MIN(month) AS month,
        MIN(day) AS day
    FROM
        session_base
    GROUP BY
        id_session
),
session_agg AS (
    SELECT
        id_session,
        COUNT(*) AS query_count,
        SUM(CASE WHEN response_category = 'data_query' THEN 1 ELSE 0 END) AS data_query_count,
        SUM(CASE WHEN response_category = 'debug' THEN 1 ELSE 0 END) AS debug_count,
        SUM(CASE WHEN NOT is_success THEN 1 ELSE 0 END) AS failed_count,
        SUM(CASE WHEN is_success THEN 1 ELSE 0 END) AS succeeded_count,
        MAX(CASE WHEN urn_count > 0 THEN TRUE ELSE FALSE END) AS used_datahub,
        MAX(CASE WHEN data_product_count > 0 THEN TRUE ELSE FALSE END) AS used_data_product,
        MAX(data_product_count) AS distinct_products,
        MAX(dataset_count) AS distinct_datasets,
        MAX(depth_tier) AS depth_tier
    FROM
        session_base
    GROUP BY
        id_session
)
SELECT
    si.id_session,
    si.user,
    si.session_source,
    si.dominant_business_domain,
    sa.query_count,
    sa.data_query_count,
    sa.debug_count,
    sa.failed_count,
    sa.succeeded_count,
    ROUND(100.0 * sa.succeeded_count / NULLIF(sa.query_count, 0), 1) AS pct_finished,
    sa.used_datahub,
    sa.used_data_product,
    sa.distinct_products,
    sa.distinct_datasets,
    sa.depth_tier,
    ROUND(
        (UNIX_TIMESTAMP(si.ts_session_end) - UNIX_TIMESTAMP(si.ts_session_start)) / 60.0,
        2
    ) AS session_duration_min,
    si.ts_session_start,
    si.ts_session_end,
    DATE(si.ts_session_start) AS dt_session,
    si.year,
    si.month,
    si.day
FROM
    session_identity AS si
INNER JOIN
    session_agg AS sa
        ON si.id_session = sa.id_session
