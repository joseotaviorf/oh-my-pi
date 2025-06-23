SELECT
    id,
    session_id AS id_session,
    event_type,
    history_payload,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_saruman_test_raw.session_history
