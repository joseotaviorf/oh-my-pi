SELECT
    CAST(id_user AS BIGINT) AS id_user,
    CAST(GET_JSON_OBJECT(event_properties, '$.house_id') AS BIGINT) AS id_house,
    GET_JSON_OBJECT(event_properties, '$.visit_code') AS visit_code,
    UPPER(GET_JSON_OBJECT(event_properties, '$.business_context')) AS business_context,
    GET_JSON_OBJECT(event_properties, '$.visit_status') AS visit_status,
    GET_JSON_OBJECT(event_properties, '$.recommendation') AS recommendation,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = 233592
    AND event_type = 'visit_finalization_agent_success_page_viewed'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
