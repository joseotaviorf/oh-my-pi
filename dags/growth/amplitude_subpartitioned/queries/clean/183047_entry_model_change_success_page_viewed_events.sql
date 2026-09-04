SELECT
    id_user,
    CAST(GET_JSON_OBJECT(event_properties, '$.house_id') AS BIGINT) AS id_house,
    GET_JSON_OBJECT(event_properties, '$.key_location') AS key_location,
    GET_JSON_OBJECT(event_properties, '$.source') AS source,
    GET_JSON_OBJECT(event_properties, '$.business_context') AS business_context,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_events_clean.events
WHERE
    id_app = 183047
    AND event_type = 'entry_model_change_success_page_viewed'
    AND year = {year} AND month = {month} AND day = {day}
