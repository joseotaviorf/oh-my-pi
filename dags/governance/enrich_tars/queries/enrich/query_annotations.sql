WITH tars_raw AS (
    SELECT
        query_id AS id_query,
        query,
        query_state,
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
        AND source = 'Tars'
),
parsed AS (
    SELECT
        id_query,
        query_state,
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
        execution_time / 1000.0 AS execution_time_sec,
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
        COALESCE(session_source, 'unknown') AS session_source,
        COALESCE(user, 'unknown') AS user,
        user_question,
        COALESCE(response_category, 'unknown') AS response_category,
        COALESCE(business_domain, 'unknown') AS business_domain,
        query_state,
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
    session_source,
    user,
    user_question,
    response_category,
    business_domain,
    query_state,
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
