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
    GET_JSON_OBJECT(event_properties, '$.targetNode') AS target_node,
    GET_JSON_OBJECT(event_properties, '$.action') AS browse_action,
    GET_JSON_OBJECT(event_properties, '$.entity') AS entity,
    GET_JSON_OBJECT(event_properties, '$.environment') AS environment,
    GET_JSON_OBJECT(event_properties, '$.platform') AS platform,
    CAST(GET_JSON_OBJECT(event_properties, '$.targetDepth') AS INT) AS target_depth,
    ts_event,
    DATE(ts_event) AS dt_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = '417002' AND event_type = 'BrowseV2SelectNodeEvent'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
