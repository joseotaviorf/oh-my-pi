SELECT
    CAST(id_user AS BIGINT) AS id_user,
    CAST(GET_JSON_OBJECT(event_properties, '$.house_id') AS BIGINT) AS id_house,
    GET_JSON_OBJECT(event_properties, '$.visit_code') AS visit_code,
    UPPER(GET_JSON_OBJECT(event_properties, '$.business_context')) AS business_context,
    GET_JSON_OBJECT(event_properties, '$.prospect_property_feedback') AS prospect_property_feedback,
    GET_JSON_OBJECT(event_properties, '$.prospect_property_feedback_options') AS prospect_property_feedback_options,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = 233592
    AND event_type = 'visit_finalization_agent_profilling_button_clicked'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
