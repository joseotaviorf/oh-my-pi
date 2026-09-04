SELECT
    id_amplitude,
    id_app,
    id_event,
    id_session,
    id_inserted,
    id_user,
    city,
    country,
    event_type,
    GET_JSON_OBJECT(event_properties, '$.entityUrn') AS entity_urn,
    GET_JSON_OBJECT(event_properties, '$.entityType') AS entity_type,    
    ts_event,    
    DATE(ts_event) AS dt_event,
    year,
    month,
    day
FROM
    datalake_amplitude_events_clean.events
WHERE
    id_app = '417002' AND event_type = 'EntityViewEvent'
    AND year = {year} AND month = {month} AND day = {day}