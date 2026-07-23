SELECT
    id_user,
    GET_JSON_OBJECT(event_properties, '$.house_id') AS id_house,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = 233592
    AND event_type = 'agent_with_keys_property_indication_copy_button_clicked'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
