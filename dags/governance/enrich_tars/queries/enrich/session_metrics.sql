WITH session_base AS (
    SELECT
        id_session,
        user,
        session_source,
        business_domain_normalized,
        is_synthetic_session,
        is_success,
        response_category,
        ts_started,
        ts_ended,
        urn_count,
        data_product_count,
        dataset_count,
        depth_tier
    FROM
        datalake_tars.query_annotations
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
),
session_identity AS (
    SELECT
        id_session,
        MIN(user) AS user,
        MIN(session_source) AS session_source,
        MAX(is_synthetic_session) AS is_synthetic_session,
        MIN(ts_started) AS ts_session_start,
        MAX(ts_ended) AS ts_session_end
    FROM
        session_base
    GROUP BY
        id_session
),
domain_counts AS (
    SELECT
        id_session,
        business_domain_normalized,
        COUNT(*) AS domain_query_count,
        ROW_NUMBER() OVER (
            PARTITION BY id_session
            ORDER BY COUNT(*) DESC, business_domain_normalized
        ) AS domain_rank
    FROM
        session_base
    GROUP BY
        id_session,
        business_domain_normalized
),
dominant_domain AS (
    SELECT
        id_session,
        business_domain_normalized AS dominant_business_domain
    FROM
        domain_counts
    WHERE
        domain_rank = 1
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
),
turn_agg AS (
    SELECT
        id_session,
        AVG(
            CASE
                WHEN start_source = 'prompt_submit'
                    AND trigger != 'scheduled'
                    AND duration_ms IS NOT NULL
                THEN duration_ms
            END
        ) AS avg_turn_duration_ms,
        SUM(CASE WHEN outcome = 'completed' THEN 1 ELSE 0 END) AS completed_turn_count,
        SUM(CASE WHEN outcome = 'gap' THEN 1 ELSE 0 END) AS gap_turn_count
    FROM
        datalake_tars.turn_metrics
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
    GROUP BY
        id_session
),
quality_agg AS (
    SELECT
        id_session,
        SUM(
            CASE
                WHEN dq_status IN ('fail', 'concern') THEN 1
                ELSE 0
            END
        ) AS dq_fail_count,
        AVG(
            CASE answer_confidence_tier
                WHEN 'high' THEN 3.0
                WHEN 'medium' THEN 2.0
                WHEN 'low' THEN 1.0
            END
        ) AS avg_confidence_tier
    FROM
        datalake_tars.turn_quality
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
        AND event_type = 'turn_summary'
    GROUP BY
        id_session
),
session_start_agg AS (
    SELECT
        id_session,
        MIN(NULLIF(tars_env, 'unknown')) AS tars_env,
        MIN(NULLIF(language, 'unknown')) AS language
    FROM
        datalake_tars_clean.vector_logs
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
        AND event_type = 'session_start'
    GROUP BY
        id_session
)
SELECT
    si.id_session,
    si.user,
    si.session_source,
    si.is_synthetic_session,
    dd.dominant_business_domain,
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
    ROUND(ta.avg_turn_duration_ms, 1) AS avg_turn_duration_ms,
    COALESCE(ta.completed_turn_count, 0) AS completed_turn_count,
    COALESCE(ta.gap_turn_count, 0) AS gap_turn_count,
    COALESCE(qa.dq_fail_count, 0) AS dq_fail_count,
    ROUND(qa.avg_confidence_tier, 2) AS avg_confidence_tier,
    ssa.tars_env,
    ssa.language,
    ROUND(
        (UNIX_TIMESTAMP(si.ts_session_end) - UNIX_TIMESTAMP(si.ts_session_start)) / 60.0,
        2
    ) AS session_duration_min,
    si.ts_session_start,
    si.ts_session_end,
    DATE(si.ts_session_start) AS dt_session,
    YEAR(DATE(si.ts_session_start)) AS year,
    MONTH(DATE(si.ts_session_start)) AS month,
    DAY(DATE(si.ts_session_start)) AS day
FROM
    session_identity AS si
INNER JOIN
    session_agg AS sa
        ON si.id_session = sa.id_session
INNER JOIN
    dominant_domain AS dd
        ON si.id_session = dd.id_session
LEFT JOIN
    turn_agg AS ta
        ON si.id_session = ta.id_session
LEFT JOIN
    quality_agg AS qa
        ON si.id_session = qa.id_session
LEFT JOIN
    session_start_agg AS ssa
        ON si.id_session = ssa.id_session
