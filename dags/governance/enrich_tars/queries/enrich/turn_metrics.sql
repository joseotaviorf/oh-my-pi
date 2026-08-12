SELECT
    COALESCE(id_turn, CONCAT('no-turn-', id_session, '-', CAST(COALESCE(turn_index, 0) AS STRING))) AS id_turn,
    id_session,
    id_conversation,
    session_source,
    session_id_source,
    turn_index,
    outcome,
    start_source,
    trigger,
    duration_ms,
    emitted_events,
    service_name,
    env,
    skill_version,
    ts_event AS ts_turn_end,
    dt_event AS dt_turn,
    year,
    month,
    day
FROM
    datalake_tars_clean.vector_logs
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
    AND "{load_end_date}"
    AND event_type = 'turn_end'
