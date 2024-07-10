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
    datalake_saruman_raw.session_history
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
