WITH tars_raw AS (
    SELECT
        query_id AS id_query,
        query,
        query_state,
        error_name,
        execution_time,
        execution_start_time AS ts_started,
        end_time AS ts_ended,
        user,
        year,
        month,
        day
    FROM
        data_platform_metrics.trino_query_complete
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
        AND LOWER(source) LIKE 'tars%'
),
parsed AS (
    SELECT
        id_query,
        query_state,
        error_name,
        execution_time,
        ts_started,
        ts_ended,
        user,
        year,
        month,
        day,
        regexp_extract(query, '/\\* tars: (\\{{.*?\\}}) \\*/', 1) AS tars_json
    FROM
        tars_raw
),
annotated AS (
    SELECT
        id_query,
        query_state,
        error_name,
        CAST(execution_time AS DOUBLE) AS execution_time_sec,
        ts_started,
        ts_ended,
        user,
        year,
        month,
        day,
        tars_json,
        tars_json IS NOT NULL
            AND LENGTH(tars_json) > 2 AS has_tars_comment,
        COALESCE(
            get_json_object(tars_json, '$.session_id'),
            CONCAT('no-session-', id_query)
        ) AS id_session,
        get_json_object(tars_json, '$.session_source') AS session_source,
        get_json_object(tars_json, '$.user_question') AS user_question,
        get_json_object(tars_json, '$.response_category') AS response_category,
        get_json_object(tars_json, '$.business_domain') AS business_domain,
        from_json(
            get_json_object(tars_json, '$.datahub_urns'),
            'ARRAY<STRING>'
        ) AS datahub_urns
    FROM
        parsed
),
enriched AS (
    SELECT
        id_query,
        id_session,
        id_session LIKE 'no-session-%' AS is_synthetic_session,
        COALESCE(session_source, 'unknown') AS session_source,
        COALESCE(user, 'unknown') AS user,
        user_question,
        COALESCE(response_category, 'unknown') AS response_category,
        COALESCE(business_domain, 'unknown') AS business_domain,
        CASE
            WHEN business_domain IS NULL OR TRIM(business_domain) = '' THEN 'unknown'
            WHEN LOWER(TRIM(business_domain)) IN (
                'for rent',
                'for rent / for sale',
                'for rent, for sale',
                'nps for rent'
            ) THEN 'For Rent'
            WHEN LOWER(TRIM(business_domain)) IN (
                'for sale',
                'for sale vc chat segmentation',
                'for_sale_visits'
            ) THEN 'For Sale'
            WHEN LOWER(TRIM(business_domain)) IN (
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
            WHEN LOWER(TRIM(business_domain)) IN ('growth', 'supply', 'leads') THEN 'Growth'
            WHEN LOWER(TRIM(business_domain)) IN (
                'conversational',
                'conversacional',
                'chatbot',
                'support_ai'
            ) THEN 'Conversational'
            WHEN LOWER(TRIM(business_domain)) = 'agents' THEN 'Agents'
            WHEN LOWER(TRIM(business_domain)) IN (
                'support and services',
                'customer_service',
                'customer_support_bpo',
                'concierge',
                'concierge reprocessamento',
                'concierge reprocessing'
            ) THEN 'Support and Services'
            WHEN business_domain IN (
                'For Rent',
                'For Sale',
                'Fintech',
                'Growth',
                'Conversational',
                'Agents',
                'Other',
                'Single Station',
                'Supply'
            ) THEN business_domain
            ELSE 'Other'
        END AS business_domain_normalized,
        query_state,
        error_name,
        query_state = 'FINISHED' AS is_success,
        execution_time_sec,
        ts_started,
        ts_ended,
        has_tars_comment,
        COALESCE(SIZE(datahub_urns), 0) AS urn_count,
        COALESCE(
            SIZE(
                FILTER(
                    datahub_urns,
                    u -> u LIKE '%dataProduct%'
                )
            ),
            0
        ) AS data_product_count,
        COALESCE(
            SIZE(
                FILTER(
                    datahub_urns,
                    u -> u LIKE '%dataset%'
                )
            ),
            0
        ) AS dataset_count,
        CASE
            WHEN COALESCE(SIZE(datahub_urns), 0) = 0 THEN 'no_datahub'
            WHEN COALESCE(
                SIZE(FILTER(datahub_urns, u -> u LIKE '%dataProduct%')),
                0
            ) > 0 THEN 'with_data_product'
            ELSE 'dataset_only'
        END AS context_mode,
        CASE
            WHEN COALESCE(SIZE(datahub_urns), 0) = 0 THEN 'L0'
            WHEN COALESCE(
                SIZE(FILTER(datahub_urns, u -> u LIKE '%dataProduct%')),
                0
            ) = 0 THEN 'L1'
            WHEN COALESCE(
                SIZE(FILTER(datahub_urns, u -> u LIKE '%dataProduct%')),
                0
            ) = 1 THEN 'L2'
            WHEN COALESCE(
                SIZE(FILTER(datahub_urns, u -> u LIKE '%dataProduct%')),
                0
            ) = 2 THEN 'L3'
            ELSE 'L4'
        END AS depth_tier,
        year,
        month,
        day
    FROM
        annotated
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
    has_tars_comment,
    urn_count,
    data_product_count,
    dataset_count,
    context_mode,
    depth_tier,
    ts_started,
    ts_ended,
    year,
    month,
    day
FROM
    enriched
