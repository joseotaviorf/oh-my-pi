SELECT
    id_amplitude,
    BIGINT(id_user) AS id_user,
    id_device,
    BIGINT(GET_JSON_OBJECT(event_properties, '$.house_id')) AS id_house,
    GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
    event_type,
    user_properties,
    event_properties,
    ts_event,
    ts_processed,
    year,
    month,
    day
FROM
    datalake_amplitude_new_clean.events
WHERE
    id_app = '183047' AND event_type = 'relisting_early_visits_confirmed'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'