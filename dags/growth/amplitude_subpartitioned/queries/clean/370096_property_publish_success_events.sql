SELECT
    CAST(GET_JSON_OBJECT(event_properties, '$.property_id') AS BIGINT) AS id_house,
    CAST(id_user AS BIGINT) AS id_user,
    UPPER(GET_JSON_OBJECT(event_properties, '$.business_context')) AS business_context,
    event_properties,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_events_clean.events
WHERE
    event_type = 'property_publish_success'
    AND id_app = 370096
    AND year = {year} AND month = {month} AND day = {day}
