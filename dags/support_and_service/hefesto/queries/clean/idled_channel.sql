SELECT
    id AS id_idled_channel,
    idled_channel_event_id AS id_idled_channel_event,
    external_channel_id AS id_channel_twilio,
    session_id AS id_session,
    status
    user_phone,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hefesto_raw.idled_channel
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
