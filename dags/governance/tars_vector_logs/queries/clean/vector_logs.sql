SELECT
    NULLIF(GET_JSON_OBJECT(raw_content, '$.session_id'), '-') AS id_session,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.turn_id'), '-') AS id_turn,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.conv_id'), '-') AS id_conversation,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.service_name'), '-') AS service_name,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.env'), '-') AS env,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.event_type'), '-') AS event_type,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.status'), '-') AS status,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.level'), '-') AS level,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.session_source'), '-') AS session_source,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.session_id_source'), '-') AS session_id_source,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.tars_env'), '-') AS tars_env,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.skill_version'), '-') AS skill_version,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.language'), '-') AS language,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.response_category'), '-') AS response_category,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.business_domain'), '-') AS business_domain,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.context_path'), '-') AS context_path,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.error_class'), '-') AS error_class,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.error_message'), '-') AS error_message,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.blocking_step'), '-') AS blocking_step,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.detail'), '-') AS detail,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.outcome'), '-') AS outcome,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.start_source'), '-') AS start_source,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.trigger'), '-') AS trigger,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.answer_confidence_tier'), '-') AS answer_confidence_tier,
    COALESCE(
        NULLIF(GET_JSON_OBJECT(raw_content, '$.dq_status'), '-'),
        NULLIF(GET_JSON_OBJECT(raw_content, '$.dq.status'), '-')
    ) AS dq_status,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.dp_urn'), '-') AS dp_urn,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.domain_name'), '-') AS domain_name,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.table'), '-') AS table_name,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.query_preview'), '-') AS query_preview,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.user_question'), '-') AS user_question,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.sql'), '-') AS sql,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.last_assistant_message_preview'), '-') AS last_assistant_message_preview,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.feedback_text'), '-') AS feedback_text,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.likert_label'), '-') AS likert_label,
    NULLIF(GET_JSON_OBJECT(raw_content, '$.user_slug'), '-') AS user_slug,
    CAST(
        NULLIF(GET_JSON_OBJECT(raw_content, '$.duration_ms'), '-') AS DOUBLE
    ) AS duration_ms,
    CAST(
        NULLIF(GET_JSON_OBJECT(raw_content, '$.row_count'), '-') AS INT
    ) AS row_count,
    CAST(
        NULLIF(GET_JSON_OBJECT(raw_content, '$.response_bytes'), '-') AS INT
    ) AS response_bytes,
    CAST(
        NULLIF(GET_JSON_OBJECT(raw_content, '$.data_product_count'), '-') AS INT
    ) AS data_product_count,
    CAST(
        NULLIF(GET_JSON_OBJECT(raw_content, '$.likert_score'), '-') AS INT
    ) AS likert_score,
    CAST(
        NULLIF(GET_JSON_OBJECT(raw_content, '$.turn_index'), '-') AS INT
    ) AS turn_index,
    CAST(
        COALESCE(
            NULLIF(GET_JSON_OBJECT(raw_content, '$.self_review_fix_cycles'), '-'),
            NULLIF(GET_JSON_OBJECT(raw_content, '$.self_review.fix_cycles'), '-')
        ) AS INT
    ) AS self_review_fix_cycles,
    CAST(
        COALESCE(
            NULLIF(GET_JSON_OBJECT(raw_content, '$.schema_gate_passed'), '-'),
            NULLIF(GET_JSON_OBJECT(raw_content, '$.schema_gate.passed'), '-')
        ) AS BOOLEAN
    ) AS is_schema_gate_passed,
    CAST(
        NULLIF(GET_JSON_OBJECT(raw_content, '$.schema_valid'), '-') AS BOOLEAN
    ) AS is_schema_valid,
    CAST(
        NULLIF(GET_JSON_OBJECT(raw_content, '$.found'), '-') AS BOOLEAN
    ) AS is_found,
    CAST(
        NULLIF(GET_JSON_OBJECT(raw_content, '$.query_executed'), '-') AS BOOLEAN
    ) AS is_query_executed,
    FROM_JSON(
        GET_JSON_OBJECT(raw_content, '$.datahub_urns'),
        'ARRAY<STRING>'
    ) AS datahub_urns,
    FROM_JSON(
        GET_JSON_OBJECT(raw_content, '$.datasets_ranked'),
        'ARRAY<STRING>'
    ) AS datasets_ranked,
    FROM_JSON(
        GET_JSON_OBJECT(raw_content, '$.emitted_events'),
        'ARRAY<STRING>'
    ) AS emitted_events,
    FROM_JSON(
        GET_JSON_OBJECT(raw_content, '$.limitations'),
        'ARRAY<STRING>'
    ) AS limitations,
    GET_JSON_OBJECT(raw_content, '$.schema_verified_tables') AS schema_verified_tables_json,
    GET_JSON_OBJECT(raw_content, '$.schema_gate') AS schema_gate_json,
    GET_JSON_OBJECT(raw_content, '$.dq') AS dq_json,
    GET_JSON_OBJECT(raw_content, '$.self_review') AS self_review_json,
    file_name,
    line_number,
    raw_content,
    CAST(GET_JSON_OBJECT(raw_content, '$.timestamp') AS TIMESTAMP) AS ts_event,
    DATE(CAST(GET_JSON_OBJECT(raw_content, '$.timestamp') AS TIMESTAMP)) AS dt_event,
    ts_load,
    year,
    month,
    day
FROM
    datalake_tars_raw.vector_logs
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
    AND "{load_end_date}"
    AND raw_content IS NOT NULL
    AND LENGTH(raw_content) > 2
