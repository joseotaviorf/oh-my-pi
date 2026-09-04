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
    GET_JSON_OBJECT(event_properties, '$.title') AS page_title,
    GET_JSON_OBJECT(event_properties, '$.path') AS page_path,
    GET_JSON_OBJECT(event_properties, '$.prevPathname') AS previous_path,
    GET_JSON_OBJECT(event_properties, '$.url') AS page_url,
    GET_JSON_OBJECT(event_properties, '$.search') AS url_query_parameter,
    ts_event,    
    DATE(ts_event) AS dt_event,
    year,
    month,
    day
FROM
    datalake_amplitude_events_clean.events
WHERE
    id_app = '417002' AND event_type = 'Page View'
    AND year = {year} AND month = {month} AND day = {day}