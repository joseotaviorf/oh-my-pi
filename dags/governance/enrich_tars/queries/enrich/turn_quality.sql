SELECT
    COALESCE(id_turn, CONCAT(event_type, '-', id_session, '-', CAST(UNIX_TIMESTAMP(ts_event) AS STRING))) AS id_turn,
    id_session,
    event_type,
    session_source,
    status,
    response_category,
    business_domain,
    context_path,
    answer_confidence_tier,
    dq_status,
    self_review_fix_cycles,
    is_schema_gate_passed,
    blocking_step,
    error_class,
    dp_urn,
    datasets_ranked,
    limitations,
    user_question,
    sql,
    duration_ms,
    service_name,
    env,
    skill_version,
    ts_event AS ts_turn,
    dt_event AS dt_turn,
    year,
    month,
    day
FROM
    datalake_tars_clean.vector_logs
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
    AND "{load_end_date}"
    AND event_type IN ('turn_summary', 'turn_blocked')
