SELECT
    CAST(id_user AS BIGINT) AS id_user,
    CAST(GET_JSON_OBJECT(event_properties, '$.house_id') AS BIGINT) AS id_house,
    GET_JSON_OBJECT(event_properties, '$.visit_code') AS visit_code,
    UPPER(GET_JSON_OBJECT(event_properties, '$.business_context')) AS business_context,
    GET_JSON_OBJECT(event_properties, '$.current_entry_model') AS current_entry_model,
    GET_JSON_OBJECT(event_properties, '$.validated_entry_model') AS validated_entry_model,
    GET_JSON_OBJECT(event_properties, '$.entry_model_validation_origin') AS entry_model_validation_origin,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = 233592
    AND event_type = 'entry_model_validation_button_clicked'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
