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
    GET_JSON_OBJECT(event_properties, '$.query') AS search_query,
    CAST(GET_JSON_OBJECT(event_properties, '$.total') AS INT) AS results_total,
    CAST(GET_JSON_OBJECT(event_properties, '$.filterCount') AS INT) AS filter_count,
    GET_JSON_OBJECT(event_properties, '$.filterMode') AS filter_mode,
    GET_JSON_OBJECT(event_properties, '$.searchVersion') AS search_version,
    GET_JSON_OBJECT(event_properties, '$.entityTypes') AS entity_types,
    GET_JSON_OBJECT(event_properties, '$.filterFields') AS filter_fields,
    ts_event,    
    DATE(ts_event) AS dt_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = '417002' AND event_type = 'SearchResultsViewEvent'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'