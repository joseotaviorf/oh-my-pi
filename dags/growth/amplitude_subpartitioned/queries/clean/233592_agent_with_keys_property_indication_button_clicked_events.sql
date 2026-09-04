SELECT
    id_user,
    GET_JSON_OBJECT(event_properties, '$.house_id') AS id_house,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_events_clean.events
WHERE
    id_app = 233592
    AND event_type = 'agent_with_keys_property_indication_button_clicked'
    AND year = {year} AND month = {month} AND day = {day}
