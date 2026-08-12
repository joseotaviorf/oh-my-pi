WITH vector_trino AS (
    SELECT
        id_session,
        session_source,
        user_question,
        response_category,
        business_domain,
        status,
        error_class,
        duration_ms,
        row_count,
        response_bytes,
        datahub_urns,
        ts_event AS ts_started,
        ts_event AS ts_ended,
        year,
        month,
        day
    FROM
        datalake_tars_clean.vector_logs
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
        AND event_type = 'trino_query'
),
trino_sessions AS (
    SELECT
        COALESCE(
            get_json_object(
                regexp_extract(query, '/\\* tars: (\\{{.*?\\}}) \\*/', 1),
                '$.session_id'
            ),
            CONCAT('no-session-', query_id)
        ) AS id_session,
        query_id AS id_query,
        user,
        query_state,
        error_name,
        CAST(execution_time AS DOUBLE) AS execution_time_sec,
        execution_start_time AS ts_trino_started,
        end_time AS ts_trino_ended,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY COALESCE(
                get_json_object(
                    regexp_extract(query, '/\\* tars: (\\{{.*?\\}}) \\*/', 1),
                    '$.session_id'
                ),
                CONCAT('no-session-', query_id)
            ),
            DATE(execution_start_time)
            ORDER BY execution_start_time
        ) AS session_query_rank
    FROM
        data_platform_metrics.trino_query_complete
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
        AND LOWER(source) LIKE 'tars%'
),
session_user AS (
    SELECT
        id_session,
        MIN(user) AS user
    FROM
        trino_sessions
    GROUP BY
        id_session
),
vector_ranked AS (
    SELECT
        id_session,
        session_source,
        user_question,
        response_category,
        business_domain,
        status,
        error_class,
        duration_ms,
        row_count,
        response_bytes,
        datahub_urns,
        ts_started,
        ts_ended,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY id_session, DATE(ts_started)
            ORDER BY ts_started
        ) AS session_query_rank
    FROM
        vector_trino
),
joined AS (
    SELECT
        COALESCE(trino.id_query, CONCAT('vector-', vr.id_session, '-', CAST(vr.session_query_rank AS STRING))) AS id_query,
        COALESCE(vr.id_session, CONCAT('no-session-', COALESCE(trino.id_query, 'unknown'))) AS id_session,
        COALESCE(vr.id_session, '') LIKE 'no-session-%' AS is_synthetic_session,
        COALESCE(vr.session_source, 'unknown') AS session_source,
        COALESCE(su.user, trino.user, 'unknown') AS user,
        vr.user_question,
        COALESCE(vr.response_category, 'unknown') AS response_category,
        COALESCE(vr.business_domain, 'unknown') AS business_domain,
        CASE
            WHEN vr.business_domain IS NULL OR TRIM(vr.business_domain) = '' THEN 'unknown'
            WHEN LOWER(TRIM(vr.business_domain)) IN (
                'for rent',
                'for rent / for sale',
                'for rent, for sale',
                'nps for rent'
            ) THEN 'For Rent'
            WHEN LOWER(TRIM(vr.business_domain)) IN (
                'for sale',
                'for sale vc chat segmentation',
                'for_sale_visits'
            ) THEN 'For Sale'
            WHEN LOWER(TRIM(vr.business_domain)) IN (
                'fintech',
                'fintech credit',
                'credito',
                'collections',
                'collections ai',
                'closing',
                'lending lra',
                'accounting',
                'accounting-recon'
            ) THEN 'Fintech'
            WHEN LOWER(TRIM(vr.business_domain)) IN ('growth', 'supply', 'leads') THEN 'Growth'
            WHEN LOWER(TRIM(vr.business_domain)) IN (
                'conversational',
                'conversacional',
                'chatbot',
                'support_ai'
            ) THEN 'Conversational'
            WHEN LOWER(TRIM(vr.business_domain)) = 'agents' THEN 'Agents'
            WHEN LOWER(TRIM(vr.business_domain)) IN (
                'support and services',
                'customer_service',
                'customer_support_bpo',
                'concierge',
                'concierge reprocessamento',
                'concierge reprocessing'
            ) THEN 'Support and Services'
            WHEN vr.business_domain IN (
                'For Rent',
                'For Sale',
                'Fintech',
                'Growth',
                'Conversational',
                'Agents',
                'Other',
                'Single Station',
                'Supply'
            ) THEN vr.business_domain
            ELSE 'Other'
        END AS business_domain_normalized,
        COALESCE(trino.query_state, CASE WHEN vr.status = 'success' THEN 'FINISHED' ELSE 'FAILED' END) AS query_state,
        COALESCE(trino.error_name, vr.error_class) AS error_name,
        COALESCE(vr.status = 'success', trino.query_state = 'FINISHED') AS is_success,
        COALESCE(trino.execution_time_sec, vr.duration_ms / 1000.0) AS execution_time_sec,
        vr.row_count,
        vr.response_bytes,
        TRUE AS has_tars_comment,
        COALESCE(SIZE(vr.datahub_urns), 0) AS urn_count,
        COALESCE(
            SIZE(FILTER(vr.datahub_urns, u -> u LIKE '%dataProduct%')),
            0
        ) AS data_product_count,
        COALESCE(
            SIZE(FILTER(vr.datahub_urns, u -> u LIKE '%dataset%')),
            0
        ) AS dataset_count,
        CASE
            WHEN COALESCE(SIZE(vr.datahub_urns), 0) = 0 THEN 'no_datahub'
            WHEN COALESCE(
                SIZE(FILTER(vr.datahub_urns, u -> u LIKE '%dataProduct%')),
                0
            ) > 0 THEN 'with_data_product'
            ELSE 'dataset_only'
        END AS context_mode,
        CASE
            WHEN COALESCE(SIZE(vr.datahub_urns), 0) = 0 THEN 'L0'
            WHEN COALESCE(
                SIZE(FILTER(vr.datahub_urns, u -> u LIKE '%dataProduct%')),
                0
            ) = 0 THEN 'L1'
            WHEN COALESCE(
                SIZE(FILTER(vr.datahub_urns, u -> u LIKE '%dataProduct%')),
                0
            ) = 1 THEN 'L2'
            WHEN COALESCE(
                SIZE(FILTER(vr.datahub_urns, u -> u LIKE '%dataProduct%')),
                0
            ) = 2 THEN 'L3'
            ELSE 'L4'
        END AS depth_tier,
        vr.datahub_urns,
        COALESCE(trino.ts_trino_started, vr.ts_started) AS ts_started,
        COALESCE(trino.ts_trino_ended, vr.ts_ended) AS ts_ended,
        vr.year,
        vr.month,
        vr.day
    FROM
        vector_ranked AS vr
    LEFT JOIN
        trino_sessions AS trino
            ON vr.id_session = trino.id_session
            AND vr.session_query_rank = trino.session_query_rank
            AND ABS(
                UNIX_TIMESTAMP(vr.ts_started) - UNIX_TIMESTAMP(trino.ts_trino_started)
            ) <= 600
    LEFT JOIN
        session_user AS su
            ON vr.id_session = su.id_session
)
SELECT
    id_query,
    id_session,
    is_synthetic_session,
    session_source,
    user,
    user_question,
    response_category,
    business_domain,
    business_domain_normalized,
    query_state,
    error_name,
    is_success,
    execution_time_sec,
    row_count,
    response_bytes,
    has_tars_comment,
    urn_count,
    data_product_count,
    dataset_count,
    context_mode,
    depth_tier,
    datahub_urns,
    ts_started,
    ts_ended,
    year,
    month,
    day
FROM
    joined
