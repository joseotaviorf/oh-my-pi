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
    GET_JSON_OBJECT(event_properties, '$.originPath') AS search_origin_path,
    GET_JSON_OBJECT(event_properties, '$.pageNumber') AS search_page_number,
    GET_JSON_OBJECT(event_properties, '$.query') AS search_query,    
    ts_event,    
    DATE(ts_event) AS dt_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = '417002' AND event_type = 'SearchEvent'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'