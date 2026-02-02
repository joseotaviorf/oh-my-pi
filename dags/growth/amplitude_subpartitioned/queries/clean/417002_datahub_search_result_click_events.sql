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
    GET_JSON_OBJECT(event_properties, '$.entityType') AS entity_type,
    GET_JSON_OBJECT(event_properties, '$.entityUrn') AS entity_urn,
    GET_JSON_OBJECT(event_properties, '$.index') AS results_index,
    GET_JSON_OBJECT(event_properties, '$.query') AS search_query,
    CAST(GET_JSON_OBJECT(event_properties, '$.total') AS INT) AS results_total,    
    DATE(ts_event) AS dt_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = '417002' AND event_type = 'SearchResultClickEvent'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'