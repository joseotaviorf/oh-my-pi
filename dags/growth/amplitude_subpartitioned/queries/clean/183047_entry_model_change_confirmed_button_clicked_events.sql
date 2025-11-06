SELECT
    id_user,
    CAST(GET_JSON_OBJECT(event_properties, '$.house_id') AS BIGINT) AS id_house,
    GET_JSON_OBJECT(event_properties, '$.key_location') AS key_location,
    GET_JSON_OBJECT(event_properties, '$.source') AS source,
    GET_JSON_OBJECT(event_properties, '$.business_context') AS business_context,
    CAST(GET_JSON_OBJECT(event_properties, '$.key_location_changed') AS BOOLEAN) AS key_location_changed,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = 183047
    AND event_type = 'entry_model_change_confirmed_button_clicked'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
