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
    GET_JSON_OBJECT(event_properties, '$.moduleId') AS recommendation_module_id,
    GET_JSON_OBJECT(event_properties, '$.renderType') AS recommendation_render_type,
    GET_JSON_OBJECT(event_properties, '$.scenarioType') AS recommendation_scenario_type,    
    DATE(ts_event) AS dt_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = '417002' AND event_type = 'RecommendationImpressionEvent'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'